#!/usr/bin/env perl
use 5.008_008;
use strict;
use warnings;

use IO::Socket;
use IO::Select;
use Data::Dumper;
use CGI qw/escapeHTML/;
use sigtrap;
use Fatal qw/open close/;

use FindBin;
use lib "$FindBin::Bin/lib";
use My::Util;

$SIG{'PIPE'} = 'IGNORE';

sub main {
    # $listen->blocking(0);
    my $listen = new IO::Socket::INET(Listen => 1, LocalPort => 8000, ReuseAddr => 1);
    my $select = new IO::Select($listen);
    while (my @ready = $select->can_read) {
        for my $sock (@ready) {
            if ($sock == $listen) {
                my $new_sock = $sock->accept;
                $new_sock->blocking(0);
                $select->add($new_sock);
            } else {
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
        } else {
            return 'remove';
        }
    } else {
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
    my $query = $2;
    if (defined $dispatch_table{$req->{method}}) {
        if (defined $dispatch_table{$req->{method}}{$uri}) {
            return &{$dispatch_table{$req->{method}}{$uri}}({
                    header => $req->{header},
                    content => $req->{content},
                    query => $query,
                    sock => $sock,
                });
        } else {
            return response_create(404, 'Not Found');
        }
    } else {
        return response_create(400, 'Bad Request');
    }
}

sub get  { my ($uri, $func) = @_; $dispatch_table{GET}{$uri} = $func; }
sub post { my ($uri, $func) = @_; $dispatch_table{POST}{$uri} = $func; }

get '/' => sub {
    my $self = shift;
    my $html = get_file('main.html');
    return response_create(200, 'OK', 'Context-Type: text/html; charset=UTF-8', $html);
};

my @comet_socks;
my @messages;
my $counter = 0;
post '/post' => sub {
    my $self = shift;

    my $query = CGI->new($self->{content});
    push @messages, {
        name => $query->param('name'),
        text => $query->param('text'),
        id => sprintf('%d%03d', time, $counter++),
        time => time,
    };
    if (@messages > 100) { shift @messages; }

    for my $client (@comet_socks) {
        my $json = make_chat_response_json($client->{last_id});

        my $s = $client->{sock};
        print $s response_create(200, 'OK',
            "Content-Type: application/json; charset=UTF-8\nConnection: close",
            $json);
        $s->close;
    }
    @comet_socks = ();

    return response_create(200, 'OK', "Content-Type: application/json; charset=UTF-8\nConnection: close", '{"status":"OK"}');
};

sub make_chat_response_json {
    my $last_id = shift;
    my @msg = grep { $_->{id} > $last_id } @messages;

    my $json = '['.
    join(',', map({
                my %data = %$_;
                '{'.
                join(',', map({ json_string_encode($_) . ':' . json_string_encode($data{$_}) } keys %data))
                .'}'
            } @msg))
    .']';

    return $json;
}

get '/get' => sub {
    my $self = shift;
    my $query = CGI->new($self->{query});
    my $last_id = $query->param('last_id');
    if (!defined $last_id || $last_id !~ /^\d+$/) {
        $last_id = 0;
    }

    if ($last_id == 0 && @messages != 0) {
        return response_create(200, 'OK',
            "Content-Type: application/json; charset=UTF-8\nConnection: close",
            make_chat_response_json($last_id));
    } else {
        push @comet_socks, { sock => $self->{sock}, last_id => $last_id };
        return undef;
    }
};

main();
exit;

my %file_cache;
sub get_file {
    my $filename = shift;
    my $mtime = (stat $filename)[9];
    if (!defined $file_cache{$filename} || $file_cache{$filename}{mtime} < $mtime) {
        open my $fh, '<', $filename;
        my @tmp = <$fh>;
        $file_cache{$filename}{data} = join '', @tmp;
        $file_cache{$filename}{mtime} = $mtime;
        close $fh;
    }
    return $file_cache{$filename}{data};
}
