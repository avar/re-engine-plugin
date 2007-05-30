use strict;
use Test::More tests => 6;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        my @keys = ("a" .. "f");

        $re->named_captures(
            FIRSTKEY => sub { shift @keys },
            NEXTKEY  => sub {
                my ($re, $lastkey, $flag) = @_;
                my $key = shift @keys;

                is(chr(ord($key)-1), $lastkey, "$lastkey value makes sense")
                    if defined $key;

                return $key;
            },
        );

        1;
    },
);

"a" =~ /a/;
my $key = join "|", keys %+;
is($key, "a|b|c|d|e|f", "key row correct");
