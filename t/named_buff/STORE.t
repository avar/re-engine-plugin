use strict;
use Test::More tests => 12;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        $re->stash( [
            {
                key => 'one',
                value => 'a',
                flags => 0,
            },
            {
                key => 'two',
                value => 'b',
                flags => 0,
            },
            {
                key => 'three',
                value => 'c',
                flags => 1,
            },
            {
                key => 'four',
                value => 'd',
                flags => 1,
            },
        ] );

        $re->named_captures(
            STORE => sub {
                my ($re, $key, $value, $flags) = @_;
                my $hv = shift @{ $re->stash };

                is($key, $hv->{key}, "key eq $key");
                is($value, $hv->{value}, "value eq $value");
                is($flags, $hv->{flags}, "flags == $flags");
            },
        );

        1;
    },
);

"a" =~ /a/;
$+{one}   = "a";
$+{two}   = "b";
$-{three} = "c";
$-{four}  = "d";


