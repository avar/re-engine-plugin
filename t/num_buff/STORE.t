use strict;
use Test::More tests => 14;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        $re->stash( [
            [ -2, "a" ],
            [ -2, "a" ],
            [ -1, "o" ],
            [ -1, "o" ],
            [  0, "e" ],
            [  0, "e" ],
            [  1, "u" ],
        ]);

        $re->num_captures(
            STORE => sub {
                my ($re, $paren, $sv) = @_;
                my $test = shift @{ $re->stash };

                is($paren, $test->[0]);
                is($sv, $test->[1]);
            },
        );

        1;
    },
);

"a" =~ /a/;

$` = "a";
${^PREMATCH} = "a";
$' = "o";
${^POSTMATCH} = "o";
$& = "e";
${^MATCH} = "e";
$1 = "u";
