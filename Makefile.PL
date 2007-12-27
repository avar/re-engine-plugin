use strict;
use inc::Module::Install;

name 're-engine-Plugin';

perl_version '5.009005';

author 'Ævar Arnfjörð Bjarmason <avar@cpan.org>';

abstract_from 'Plugin.pod';
license_from 'Plugin.pod';

# t/
build_requires 'Test::More' => 0; # 5.007003

tests 't/*.t t/*/*.t t/*/*/*.t';

auto_install;
WriteAll;
