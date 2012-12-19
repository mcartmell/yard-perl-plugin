# What?

Forked from [pvande](https://github.com/pvande)'s [yard-perl-plugin](https://github.com/pvande/yard-perl-plugin), this 
adds the option to write yard tags alongside or inside POD, and will attempt to match up POD-documented subroutines and modules. 
This means that Perl code documented with plain POD will look okay, and if you include YARD tags too it'll look awesome.

See [the original readme](https://github.com/pvande/yard-perl-plugin/blob/master/README.md)

# Usage

  yard -e ../yard-perl-plugin/lib/yard-perl-plugin.rb test.pm 

# Example

```
=head1 NAME

Test

=head1 DESCRIPTION

Just another module

=head1 METHODS

=item foo

    $self->foo(text => 'This is an example');

Do something

@param %args [Hash] The options for foo
@option %args text [String] The text to print

=back

=back

=cut

package Test;

sub foo {
	my %args = @_;
	print $args{text}
}

1;
```
