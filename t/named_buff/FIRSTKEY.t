use strict;
use Test::More tests => 10;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        my $stash = 0;
        my @stash = (
            {
                key => "a",
                flags => 0,
                ret => "b",
            },
            {
                key => "c",
                flags => 1,
                ret => "d",
            },
        );

        $re->named_captures(
            FIRSTKEY => sub {
                my ($re, $flags) = @_;
                my $hv = $stash[$stash];

                return $hv->{key};
            },
            FETCH => sub {
                my ($re, $key, $flags) = @_;
                my $hv = $stash[$stash++];

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
my ($k, $v);

($k, $v) = each %+;
is($k, "a");
is($v, "b");

($k, $v) = each %-;
is($k, "c");
is($v, "d");
