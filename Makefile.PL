use inc::Module::Install;
name 'Zacro';
all_from 'lib/Zacro.pm';

requires 'parent';
requires 'Memcached::Server';
requires 'SUPER';
requires 'AnyEvent';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
test_requires 'AnyEvent::Memcached';
auto_set_repository;
auto_include;
WriteAll;
