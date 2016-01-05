package AnyEvent::eris::Server;
use strict;
use warnings;
use Scalar::Util;
use Sys::Hostname;
use AnyEvent::Handle;
use AnyEvent::Socket;
use AnyEvent::Graphite;

my @_STREAM_NAMES     = qw(subscribers match debug full regex);
my %_STREAM_ASSISTERS = (
    subscribers => 'programs',
    match       => 'words',
);

# Precompiled Regular Expressions
my %_PRE = (
    program => qr/\s+\d+:\d+:\d+\s+\S+\s+([^:\s]+)(:|\s)/,
);

my $CLIENT_ID = 1;

sub _server_error {
    my ( $self, $err_str ) = @_;
    my $err_num = $err_str+0;
    AE::log debug => "SERVER ERROR: $err_num, $err_str";

    if ( $err_num == 98 ) {
        undef $self->{'_cv'};
    }
}

my %client_commands = (
    fullfeed    => qr{^fullfeed},
    nofullfeed  => qr{^nofull(feed)?},
    subscribe   => qr{^sub(?:scribe)?\s(.*)},
    unsubscribe => qr{^unsub(?:scribe)?\s(.*)},
    match       => qr{^match (.*)},
    nomatch     => qr{^nomatch (.*)},
    debug       => qr{^debug},
    nobug       => qr{^no(de)?bug},
    regex       => qr{^re(?:gex)?\s(.*)},
    noregex     => qr{^nore(gex)?},
    status      => qr{^status},
    dump        => qr{^dump\s(\S+)},
    quit        => qr{(exit|q(uit)?)},
);

sub handle_fullfeed {}
sub handle_nofullfeed {}
sub handle_subscribe {}
sub handle_unsubscribe {}
sub handle_match {}
sub handle_nomatch {}
sub handle_debug {}
sub handle_nobug {}
sub handle_regex {}
sub handle_noregex {}
sub handle_status {}
sub handle_dump {}
sub handle_quit {}

sub hangup_client {
    my ( $self, $id ) = @_;
    delete $self->clients->{$id};
    delete $self->{'_buffers'}{$id};
    $self->remove_all_streams($id);
    AE::log "Client Termination Posted: $id";
}

sub remove_stream {
    my ( $self, $id, $stream ) = @_;
    AE::log debug => "Removing '$stream' for $id";
}

sub remove_all_streams {
    my ( $self, $id ) = @_;
    foreach my $stream (@_STREAM_NAMES) {
        $self->remove_stream( $id, $stream );
    }
}

sub new {
    my $class = shift;
    my $self  = bless {
        ListenAddress  => '127.0.0.1', # "localhost" doesn't work :/
        ListenPort     => 9514,
        GraphitePort   => 2003,
        GraphitePrefix => 'eris.dispatcher',
        @_,
    }, $class;

    my ( $host, $port ) = @{$self}{qw<ListenAddress ListenPort>};
    Scalar::Util::weaken( my $inner_self = $self );

    $self->{'_tcp_server_guard'} ||= tcp_server $host, $port, sub {
        my ($fh) = @_
           or return $inner_self->_server_error($!);

        $CLIENT_ID++;
        my $handle; $handle = AnyEvent::Handle->new(
            fh       => $fh,
            on_error => sub {
                $inner_self->_server_error( $_[2] );
                $_[0]->destroy;
            },

            on_eof => sub {
                my ($hdl) = @_;
                $inner_self->hangup_client("$hdl");
                $hdl->destroy;
            },
        );

        $handle->push_write("EHLO Streamer (KERNEL: $$:$CLIENT_ID)\n");
        $inner_self->register_client("$_[0]");

        # XXX use $CLIENT_ID instead?
        # XXX $heap->{'client'} seems like another heap
        #     no point in having two, i think
        # $heap->{'clients'}{$SID} = $heap->{'client'}

        $inner_self->{'clients'}{$handle} = {};

        # POE handler: client_input
        $handle->push_read( sub {
            my ($hdl) = @_;
            my $input = $hdl->rbuf
                or return;

            foreach my $command ( keys %client_commands ) {
                my $regex = $client_commands{$command};
                if ( my ($args) = ( $input =~ /$regex/i ) ) {
                    my $method = "handle_$command";
                    return $inner_self->$method($args);
                }
            }

            $hdl->push_write("UNKNOWN COMMAND, Ignored.\015\012");
        });
    };

    return $self;
}

sub run {
    my $self       = shift;
    $self->{'_cv'} = shift || AE::cv;
    $self->{'_cv'}->recv;
}

sub clients {
    my $self = shift;
    $self->{'clients'} ||= {};
}

sub register_client {
    my ( $self, $id ) = @_;
    $self->{'_buffers'}{$id} = [];
}

1;
