#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(lib);
use Test::More tests => 1;

use My::Util;

is json_string_encode(q{\n\t"'}), q{"\\\\n\\\\t\\"'"};
