=pod

Test the C<free> method

=cut

use strict;
use Test::More skip_all => "Doesn't work currently (where did my scope go?!)";

use re::engine::Plugin (
    comp => sub {
        my ($re) = @_;

        $re->free( sub { pass "ran free" } );
    }
);

"str" ~~ /pattern/;
