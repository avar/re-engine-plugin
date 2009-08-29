use strict;
use Test::More tests => 7;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        $re->num_captures(
            FETCH => sub {
                my ($re, $paren) = @_;

                my %ret = (
                    -2 => 10,
                    -1 => 20,
                     0 => 30,
                     1 => 40,
                );

                $ret{$paren};
            }
        );

        1;
    },
);

"a" =~ /a/;

is($`, 10, '$`');
is(${^PREMATCH}, 10, '${^PREMATCH}');
is($', 20, q($'));
is(${^POSTMATCH}, 20, '${^POSTMATCH}');
is($&, 30, '$&');
is(${^MATCH}, 30, '${^MATCH}');
is($1, 40, '$1');
