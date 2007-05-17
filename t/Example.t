use strict;
use lib 't';
use Test::More tests => 1;

use Example;

"str" =~ /pattern/;

is($1, "str_1");
