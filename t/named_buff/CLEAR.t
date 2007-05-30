use strict;
use Test::More tests => 6;

use re::engine::Plugin (
    exec => sub {
        my $re = shift;

        $re->stash( [
            { flags => 0 },
            { flags => 0 },
            { flags => 0 },
            { flags => 1 },
            { flags => 1 },
            { flags => 1 },
        ] );

        $re->named_captures(
            CLEAR => sub {
                my ($re, $flags) = @_;
                my $hv = shift @{ $re->stash };

                is($flags, $hv->{flags}, "flags == $flags");
            },
        );

        1;
    },
);

"a" =~ /a/;
%+ = ();
%+ = (a => 1);
undef %+;
%- = ();
%- = (b => 1);
undef %-;


