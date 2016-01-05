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
    my ( $self, $SID ) = @_;
    delete $self->clients->{$SID};
    delete $self->{'_buffers'}{$SID};
    $self->remove_all_streams($SID);
    AE::log debug => "Client Termination Posted: $SID";
}

sub remove_stream {
    my ( $self, $SID, $stream ) = @_;
    AE::log debug => "Removing '$stream' for $SID";
}

sub remove_all_streams {
    my ( $self, $SID ) = @_;
    foreach my $stream (@_STREAM_NAMES) {
        $self->remove_stream( $SID, $stream );
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

        my $handle; $handle = AnyEvent::Handle->new(
            fh       => $fh,
            on_error => sub {
                $inner_self->_server_error( $_[2] );
                $_[0]->destroy;
            },

            on_eof => sub {
                my ($hdl) = @_;
                my $SID = $self->_gen_session_id($hdl);
                $inner_self->hangup_client($SID);
                $hdl->destroy;
                AE::log debug => "SERVER, client $SID disconnected.";
            },
        );

        my $SID = $self->_gen_session_id($handle);
        $handle->push_write("EHLO Streamer (KERNEL: $$:$SID)\n");
        $inner_self->register_client($SID);

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
    my ( $self, $SID ) = @_;
    $self->clients->{$SID}    = {};
    $self->{'_buffers'}{$SID} = [];
}

sub _gen_session_id {
    my ( $self, $handle ) = @_;
    # AnyEvent::Handle=HASH(0x1bb30f0)
    "$handle" =~ /\D0x([a-fA-F0-9]+)/;
    return $1;
}

1;
