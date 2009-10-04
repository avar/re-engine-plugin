use 5.010;
use ExtUtils::MakeMaker;

my $dist = 're-engine-Plugin';

my %META = (
 configure_requires => {
  'ExtUtils::MakeMaker' => 0,
 },
 build_requires => {
  'ExtUtils::MakeMaker' => 0,
  'Test::More'          => 0,
 },
 dynamic_config => 0,
 resources => {
  bugtracker => "http://rt.cpan.org/NoAuth/ReportBug.html?Queue=$dist",
  homepage   => "http://search.cpan.org/dist/$dist/",
  license    => 'http://dev.perl.org/licenses/',
  repository => "http://git.profvince.com/?p=perl%2Fmodules%2F$dist.git",
 },
);

WriteMakefile(
    NAME             => 're::engine::Plugin',
    AUTHOR           => 'Vincent Pit <perl@profvince.com>',
    LICENSE          => 'perl',
    ABSTRACT_FROM    => 'Plugin.pod',
    VERSION_FROM     => 'Plugin.pm',
    PL_FILES         => {},
    PREREQ_PM        => {
        'XSLoader' => 0,
    },
    MIN_PERL_VERSION => 5.010,
    META_MERGE       => \%META,
    dist             => {
        PREOP    => 'pod2text Plugin.pod > $(DISTVNAME)/README',
        COMPRESS => 'gzip -9f', SUFFIX => 'gz'
    },
    clean            => {
        FILES => "$dist-* *.gcov *.gcda *.gcno cover_db Debian_CPANTS.txt"
    },
    test             => {
        TESTS => 't/*.t t/*/*.t t/*/*/*.t',
    },
);
