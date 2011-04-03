package My::Util;
use strict;
use warnings;
use 5.008_008;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(request_parse response_create json_string_encode);

sub request_parse {
    my $request = shift;
    $request = '' unless defined $request;

    my ($first_line, $header, $content) = $request =~ /^(.+?)\r?\n((?:.*?\r?\n)*)\r?\n(.*)$/s;
    $first_line = '' unless defined $first_line;
    $header = '' unless defined $header;
    $content = '' unless defined $content;

    my ($method, $uri, $protocol) = split ' ', $first_line;
    $method = '' unless defined $method;
    $uri = '' unless defined $uri;
    $protocol = '' unless defined $protocol;

    $header =~ s/\r\n/\n/g;
    return { method => $method, uri => $uri, header => $header, content => $content };
}

sub response_create {
    my ($code, $message, $header, $content) = @_;
    $code = 200 unless defined $code;
    $message = 'OK' unless defined $message;
    $header = '' unless defined $header;
    $content = '' unless defined $content;

    $code =~ s/\D//g;
    $message =~ s/[\r\n]//g;
    $header =~ s/\r//g;
    $header =~ s/\n{2,}//g;
    $header =~ s/\n+$//sm;

    my $length = length $content;
    $header = ($header ne '' ? "$header\n" : '') . "Content-Length: $length\n";
    $header =~ s/\n/\r\n/g;
    return "HTTP/1.0 $code $message\r\n$header\r\n$content";
}

sub json_string_encode {
    my $str = shift;
    $str =~ s/\\/\\\\/g;
    $str =~ s/"/\\"/g;
    return qq{"$str"};
}

1;
