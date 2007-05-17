use strict;
use Test::More tests => 7;
use re::engine::Plugin (
    exec => sub {
        my ($re, $str) = @_;

        is_deeply($str, $re->str);

        return 1;
    },
);

my $sv;
"SCALAR" =~ \$sv;
"REF"    =~ \\$sv;
"ARRAY"  =~ [];
"HASH"   =~ {};
"GLOB"   =~ \*STDIN;
"CODE"   =~ sub {};
"main"   =~ bless {} => "main";

