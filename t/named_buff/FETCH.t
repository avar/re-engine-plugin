use strict;
use Test::More tests => 16;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        $re->stash( [
            {
                key => "a",
                flags => 0,
                ret => "b",
            },
            {
                key => "c",
                flags => 0,
                ret => "d",
            },
            {
                key => "e",
                flags => 1,
                ret => "f",
            },
            {
                key => "g",
                flags => 1,
                ret => \%ENV,
            },
        ] );

        $re->named_captures(
            FETCH => sub {
                my ($re, $key, $flags) = @_;
                my $hv = shift @{ $re->stash };

                is($key, $hv->{key}, "key == $key");
                is($flags, $hv->{flags}, "flags == $flags");
                is($hv->{ret}, $hv->{ret}, "ret = $hv->{ret}");
                return $hv->{ret};
            },
        );

        1;
    },
);

"a" =~ /a/;
cmp_ok($+{a}, 'eq', "b");
cmp_ok($+{c}, 'eq', "d");
cmp_ok($-{e}, 'eq', "f");
cmp_ok($-{g}, '==', \%ENV);
