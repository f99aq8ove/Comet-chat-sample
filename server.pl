#!/usr/bin/env perl
use 5.008_008;
use strict;
use warnings;

use IO::Socket;
use IO::Select;
use Data::Dumper;
use CGI qw/escapeHTML/;
use sigtrap;

use FindBin;
use lib "$FindBin::Bin/lib";
use My::Util;

$SIG{'PIPE'} = 'IGNORE';

sub main {

    # $listen->blocking(0);
    my $listen = new IO::Socket::INET(Listen => 1, LocalPort => 8000,
        ReuseAddr => 1);
    my $select = new IO::Select($listen);
    while (my @ready = $select->can_read) {
        for my $sock (@ready) {
            if ($sock == $listen) {
                my $new_sock = $sock->accept;
                $new_sock->blocking(0);
                $select->add($new_sock);
            }
            else {
                my $res = buffered_process($sock);
                if ($res eq 'close' || $res eq 'remove') {
                    $select->remove($sock);
                }
                if ($res eq 'close') {
                    $sock->close;
                }
            }
        }
    }
}

my %sock_buf;

sub buffered_process {
    my $sock = shift;
    my $read_length = sysread $sock, my $buf, 4096;
    if (!defined $read_length || $read_length == 0) {
        warn 'connection broken';
        return 'close';
    }

    $sock_buf{$sock} .= $buf;
    if ($sock_buf{$sock} =~ /(?:\r\n){2}/) {
        my $req = request_parse($sock_buf{$sock});
        if (length $req->{content} < get_content_length($req->{header})) {
            return '';
        }

        my $response = dispatch($sock, $req);
        delete $sock_buf{$sock};
        if (defined $response) {
            print $sock $response;
            return 'close';
        }
        else {
            return 'remove';
        }
    }
    else {
        return '';
    }
}

sub get_content_length {
    my $header = shift;
    for my $line (split /\n/, $header) {
        if ($line =~ /^Content-Length: (\d+)/) {
            return $1;
        }
    }
    return 0;
}

my %dispatch_table;

sub dispatch {
    my ($sock, $req) = @_;

    $req->{uri} =~ /^(.+?)(?:\?(.+))?$/;
    my $uri = $1;
    $uri =~ s/\.{2,}/_/g;
    my $query = $2;
    if (defined $dispatch_table{ $req->{method} }) {
        for (@{ $dispatch_table{ $req->{method} } }) {
            if (my @uri_match = $uri =~ /^$_->{uri}$/) {
                return &{ $_->{func} }(
                    {   header    => $req->{header},
                        content   => $req->{content},
                        query     => $query,
                        sock      => $sock,
                        uri_match => \@uri_match,
                    }
                );
            }
        }
        return response_create(404, 'Not Found');
    }
    else {
        return response_create(400, 'Bad Request');
    }
}

sub get {
    my ($uri, $func) = @_;
    push @{ $dispatch_table{GET} }, { uri => $uri, func => $func };
}

sub post {
    my ($uri, $func) = @_;
    push @{ $dispatch_table{POST} }, { uri => $uri, func => $func };
}

get '/' => sub {
    my $self = shift;
    my $html = get_file('main.html');
    return response_create(200, 'OK',
        'Content-Type: text/html; charset=UTF-8', $html);
};

get '/s/(.+/)?([^/]+)\.([^./]+)' => sub {
    my $self = shift;
    my ($path, $filename, $ext) = @{ $self->{uri_match} };

    my $content_type = do {    # FIXME: ugly...
        my %content_type_table = (
            html => 'text/html; charset=UTF-8',
            js   => 'text/javascript; charset=UTF-8',
        );
        defined $content_type_table{$ext}
            ? $content_type_table{$ext}
            : 'text/html; charset=UTF-8';
    };

    if (defined(
            my $file
                = get_file('s/' . undef_to_blank($path) . "$filename.$ext")
        )
        )
    {
        return response_create(200, 'OK', 'Content-Type: ' . $content_type,
            $file);
    }
    else {
        return response_create(404, 'Not Found');
    }
};

sub undef_to_blank {
    my $str = shift;
    return defined $str ? $str : '';
}

my @comet_socks;
my @messages;
my $counter   = 0;
my $last_time = 0;
post '/post' => sub {
    my $self = shift;

    my $query = CGI->new($self->{content});
    my $time  = time;
    if ($time == $last_time) {
        $counter++;
    }
    else {
        $last_time = $time;
        $counter   = 0;
    }
    push @messages,
        {
        name => undef_to_blank($query->param('name')),
        text => undef_to_blank($query->param('text')),
        id   => sprintf('%d%03d', $time, $counter),
        time => time,
        };
    if (@messages > 100) { shift @messages; }

    for my $client (@comet_socks) {
        my ($json, undef) = make_chat_response_json($client->{last_id});

        my $s = $client->{sock};
        print $s response_create(
            200,
            'OK',
            "Content-Type: application/json; charset=UTF-8\nConnection: close",
            $json
        );
        $s->close;
    }
    @comet_socks = ();

    return response_create(200, 'OK',
        "Content-Type: application/json; charset=UTF-8\nConnection: close",
        '{"status":"OK"}');
};

sub make_chat_response_json {
    my $last_id = shift;
    my @msg = grep { $_->{id} > $last_id } @messages;

    my $json = '[' . join(
        ',',
        map({   my %data = %$_;
                    '{'
                    . join(
                    ',',
                    map({         json_string_encode($_) . ':'
                                . json_string_encode($data{$_})
                        } keys %data)
                    )
                    . '}'
            } @msg)
    ) . ']';

    return ($json, scalar @msg);
}

get '/get' => sub {
    my $self    = shift;
    my $query   = CGI->new($self->{query});
    my $last_id = undef_to_blank($query->param('last_id'));
    if ($last_id !~ /^\d+$/) {
        $last_id = 0;
    }

    my ($json, $num) = make_chat_response_json($last_id);
    if ($num) {
        return response_create(
            200,
            'OK',
            "Content-Type: application/json; charset=UTF-8\nConnection: close",
            $json
        );
    }
    else {
        push @comet_socks, { sock => $self->{sock}, last_id => $last_id };
        return undef;
    }
};

main();
exit;

my %file_cache;

sub get_file {
    my $filename = shift;
    my $mtime    = (stat $filename)[9];
    if (!defined $file_cache{$filename}
        || $file_cache{$filename}{mtime} < $mtime)
    {
        open my $fh, '<', $filename or return undef;
        my @tmp = <$fh>;
        $file_cache{$filename}{data} = join '', @tmp;
        $file_cache{$filename}{mtime} = $mtime;
        close $fh;
    }
    return $file_cache{$filename}{data};
}
