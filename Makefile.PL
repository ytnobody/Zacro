use inc::Module::Install;
name 'Zacro';
all_from 'lib/Zacro.pm';

requires 'parent';
requires 'Memcached::Server';
requires 'AnyEvent';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
test_requires 'Test::TCP';
test_requires 'AnyEvent::Memcached';
test_requires 'Cache::Memcached::Fast';
test_requires 'Proc::Simple';
test_requires 'Guard';

install_script 'bin/zacrod';

auto_set_repository;
auto_include;
WriteAll;
