module YARD
  module Parser
    module Perl
      class Code
        attr_accessor :content, :line, :filename, :group

        def initialize(args)
          @content  = args[:content]
          @line     = args[:lnum]
          @filename = args[:filename]

          @comments = ''
          @name     = ''
        end

        def comments_range
          (@line - @comments.split.length)...@line
        end

        def inspect
          "<#{self.class} #{@name} #{@filename}:#{@line}>"
        end

        def show
          "sub #{@name} in #{@filename}:#{@line}"
        end
      end

      class Comment < Code
        def to_s
          str = @content.gsub(/^\s*#/, '')
          str.gsub!(/^ /, '') while str.lines.any? { |line| line =~ /^ / } && str.lines.all? { |line| line =~ /^ |^$/ }
          str
        end

        def lines
          @line...(@line - 1 + @content.split("\n").length)
        end
				
				def initialize(args)
					super
				end

				class PodBlock < Comment

					def initialize(args)
						super
						@pkg_description = nil
						if m = @content.match(/=head\d NAME\n\n(\S+).*?=head\d DESCRIPTION(.*)?^=/ms)
							@pkg_description = [m[1], m[2]]
						end
					end

					def pkg_description
						@pkg_description
					end

					def to_s
						str = @content.lines.grep(/^[^\s=]/).join('')
						str
					end

					def sub_for
						if m = @content.match(/=item\s+([^\n]+)/)
							return m[1]
						end
						return
					end
				end
      end

      class Package < Code
        attr_accessor :comments, :comments_hash_flag, :name, :superclass

        def namespace
          "::#{@name}".split("::")[0...-1].join("::")
        end

        def classname
          "::#{@name}".split("::")[-1]
        end
      end

      class Sub < Code
        attr_accessor :comments, :comments_hash_flag, :comments_range, :name, :body
        attr_writer   :visibility

        def visibility
          @visibility ||= @name.start_with?('_') ? :protected : :public
        end

        def parameters
          return @parameters if @parameters

          @parameters = [].tap do |params|
            @body.strip.lines.take_while do |line|
              if line.strip =~ /my\s+(.*?)\s*=\s*shift(\(\s*@_\s*\))?\s*;/
                params << [$1,nil]
              elsif line.strip =~ /my\s+\((.*?)\)\s*=\s*@_\s*;/
									$1.split(/\s*(?:,|=>)\s*/).map { |e| [e, nil] }.each do |param|
										params << param
									end
                  false
              else
                false
              end
            end
          end
        end
      end

      class PerlParser < YARD::Parser::Base
        def initialize(source, filename)
          @source = source
          @filename = filename
        end

        def parse
          PerlSyntax.parse(@source, @processor = Processor.new(@filename))

          group   = nil
					comments_for = {}

          watches = {
            # Watch for contiguous comment blocks
            'meta.comment.block' => proc { |s, e| s << Comment.new(e) },

						'comment.block.documentation.perl' =>  proc do |s, e|
							pb = Comment::PodBlock.new(e)
							if pkgd = pb.pkg_description
								comments_for[pkgd[0]] = pkgd[1]
							elsif subname = pb.sub_for
								comments_for[subname] = pb
							end
							s << pb
						end,

            # Watch for 'package' declarations
            'meta.class' => proc do |s, e|
              pkg = Package.new(e)
              pkg.comments += s.pop.to_s if s.last.is_a?(Comment) && s.last.lines.end == (pkg.line - 1)
              index = s.length

              # Watch for the package name
              watches['entity.name.type.class'] = proc do |_, e2|
                pkg.name = e2[:content]
                watches.delete('entity.name.type.class')
              end

              # Watch the upcoming 'use' statements
              watches['meta.import.package'] = proc do |_, e|
                case e[:content]
                when /^bas(e|i[sc])|parent$/
                  # First argument will be the superclass name
                  watches['meta.import.arguments'] = proc do |_, e|
                    pkg.superclass = e[:content][/(\w|:)+/]
                    watches.delete('meta.import.arguments')
                  end
                when 'namespace::clean'
                  # Privatize every sub already declared in this package
                  s[index..-1].select { |e| e.is_a?(Sub) }.each do |sub|
                    sub.visibility = :private
                  end
                end
              end

              s << pkg
            end,

            # Watch for individual comment lines
            'meta.comment.full-line' => proc do |s, e|
              case e[:content]
                # Group detection
                when /#\s*@group\s+(.*)/ then group = $1
                when /#\s*@endgroup/     then group = nil
              end
            end,

            # Watch for named function declarations
            'meta.function.named' => proc do |s, e|
              sub = Sub.new(e)
              sub.comments = s.pop.to_s if s.last.class == Comment && s.last.lines.end == (sub.line - 1)
              sub.group    = group      unless group.nil?

              # Watch for the function name
              watches['entity.name.function'] = proc do |_, e|
                sub.name = e[:content]
                watches.delete('entity.name.function')
              end

              # Watch for the function body
              watches['meta.scope.function'] = proc do |_, e|
                sub.body = e[:content]
                watches.delete('meta.scope.function')
              end

              s << sub
            end
          }

          @processor.map { |x| x[:filename] = @filename }

          @stack = @processor.inject([]) do |stack, elem|
						procs = []
            watches.each_pair do |key, val|
              procs.push(val) if elem[:scope] == key
            end
						procs.each do |p|
							p.call(stack, elem)
						end
            stack
          end
					@stack.each do |e|
						if (e.is_a?(Sub) || e.is_a?(Package)) && comments_for.has_key?(e.name)
							e.comments = comments_for[e.name].to_s + e.comments
						end
					end
        end

        def enumerator
          @stack
        end
      end

      class Processor
        class Scope
          def initialize(name)
            @scope = name.split('.')
          end

          def ==(obj)
            obj.split('.').each_with_index do |element, index|
              element == @scope[index] or return false
            end
            return true
          end
        end

        def initialize(filename)
          @file = filename
          @line = ''
          @lnum = 0

          @cache = []
          @stash = []
        end

        def start_parsing(name); end
        def end_parsing(name);   end

        def new_line(line)
          @line = line
          @lnum += 1
          @stash.each { |x| x[:content] << @line }
        end

        def open_tag(name, pos)
          obj = {
            :scope_name => name,
            :scope => Scope.new(name),
            :lnum => @lnum,
            :range => (pos..-1),
            :content => @line.dup
          }
          @cache << (obj)
          @stash.unshift(obj)
        end

        def close_tag(name, pos)
          closed = @stash.delete_at(@stash.index(@stash.find { |e| e[:scope_name] == name }))
          start = closed.delete(:range).begin
          closed[:content] = closed[:content][start...(pos - @line.length)]
        end

        include Enumerable
        def each(*args, &blk)
          @cache.each(*args, &blk)
        end
      end
    end
  end
end
