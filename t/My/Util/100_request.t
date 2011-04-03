#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(lib);
use Test::More tests => 3;

use My::Util;

is_deeply request_parse(<<"..."), { method => 'GET', uri => '/', header => "Accept-Encoding: gzip, deflate\nConnection: Keep-Alive\n", content => '', };
GET / HTTP/1.1\r
Accept-Encoding: gzip, deflate\r
Connection: Keep-Alive\r
\r
...

is_deeply request_parse(<<"..."), { method => 'POST', uri => '/', header => "", content => "hoge\n", };
POST / HTTP/1.1\r
\r
hoge
...

is_deeply request_parse(<<"..."), { method => '', uri => '', header => '', content => '', };
...
