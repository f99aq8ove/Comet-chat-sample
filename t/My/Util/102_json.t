#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(lib);
use Test::More tests => 3;

use My::Util;

is json_string_encode(q{\n\t"'}), q{"\\\\n\\\\t\\"'"};
is json_string_encode(qq{\n\n\t\t}), q{"\\n\\n\\t\\t"};
is json_string_encode(qq{\0 \x1f~\x7f}), q{" ~"};
