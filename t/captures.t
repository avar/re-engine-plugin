=pod

Test the B<captures> method

=cut

use strict;

use feature ':5.10';

#use Test::More tests => 1;
use Test::More skip_all => 'TODO: implement';

use re::engine::Plugin (
    comp => sub {
        my $re = shift;
    },
    exec => sub {
        my ($re, $str) = @_;

        # 
        #$re->captures( [ 1 .. 4 ] );
        #$re->captures( sub {} );

        $re->named_captures( );

        1; # matched
    }
);

if ("string" =~ /./g) {
    cmp_ok $1, '==', 1337;
    cmp_ok $+{named}, '==', 5;
}
