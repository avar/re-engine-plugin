use strict;
use Test::More tests => 6;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        $re->stash( [
            { key => "boob", flags => 0, ret => 1 },
            { key => "ies",  flags => 1, ret => 0 },
        ] );

        $re->named_captures(
            EXISTS => sub {
                my ($re, $key, $flags) = @_;
                my $hv = shift @{ $re->stash };

                is($key, $hv->{key}, "key == $key");
                is($flags, $hv->{flags}, "flags == $flags");
                return $hv->{ret};
            },
        );

        1;
    },
);

"a" =~ /a/;
ok(exists $+{boob});
ok(!exists $-{ies});;

