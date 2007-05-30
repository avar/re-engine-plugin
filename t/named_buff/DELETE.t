use strict;
use Test::More tests => 4;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        $re->stash( [
            {
                key => 'one',
                flags => 0,
            },
            {
                key => 'two',
                flags => 1,
            },
        ] );

        $re->named_captures(
            DELETE => sub {
                my ($re, $key, $flags) = @_;
                my $hv = shift @{ $re->stash };

                is($key, $hv->{key}, "key eq $key");
                is($flags, $hv->{flags}, "flags == $flags");
            },
        );

        1;
    },
);

"a" =~ /a/;
delete $+{one};
delete $-{two};


