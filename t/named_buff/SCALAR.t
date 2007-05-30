use strict;
use Test::More tests => 6;

use re::engine::Plugin (
    exec => sub {
        my ($re) = @_;

        my @stash = (
            { flags => 0, ret => "ook" },
            { flags => 1, ret => "eek" },
        );

        $re->named_captures(
            SCALAR => sub {
                my ($re, $flags) = @_;
                my $hv = shift @stash;

                is($flags, $hv->{flags}, "flags == $flags");
                ok($hv->{ret}, "ret == $hv->{ret}");

                return $hv->{ret};
            },
        );

        1;
    },
);

"a" =~ /a/;
is(scalar %+, "ook");
is(scalar %-, "eek");
