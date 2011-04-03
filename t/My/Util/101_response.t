#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(lib);
use Test::More tests => 4;

use My::Util;

is response_create(200, 'OK', "Connection: Close\n"), <<"...";
HTTP/1.0 200 OK\r
Connection: Close\r
Content-Length: 0\r
\r
...

is response_create(200, 'OK', '', ''), <<"...";
HTTP/1.0 200 OK\r
Content-Length: 0\r
\r
...

is response_create(200, 'OK'), <<"...";
HTTP/1.0 200 OK\r
Content-Length: 0\r
\r
...

is response_create(200, 'OK', "Content-Type: text/plain\nConnection: close", "hoge\n"), <<"...";
HTTP/1.0 200 OK\r
Content-Type: text/plain\r
Connection: close\r
Content-Length: 5\r
\r
hoge
...
