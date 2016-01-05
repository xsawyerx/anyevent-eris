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
    my ( $self, $err_str, $fatal ) = @_;
    my $err_num = $!+0;
    AE::log debug => "SERVER ERROR: $err_num, $err_str";

    $fatal and $self->{'_cv'}->send;
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

sub handle_subscribe {
    my ( $self, $handle, $SID, $args ) = @_;

    $self->remove_stream( $SID, 'full' );

    my @programs = map lc, split /[\s,]+/, $args;
    foreach my $program (@programs) {
        # FIXME: add this to the SID heap instead
        $self->{'_subscribers'}{$SID}{$program} = 1;

        # number of registered programs
        $self->{'_programs'}{$program}++;
    }

    $handle->push_write(
        'Subscribed to : '     .
        join( ',', @programs ) .
        "\n"
    );
}

sub handle_unsubscribe {
    my ( $self, $handle, $SID, $args ) = @_;

    my @programs = map lc, split /[\s,]+/, $args;
    foreach my $program (@programs) {
        delete $self->{'_subscribers'}{$SID}{$program};
        $self->{'_programs'}{$program}--;
        delete $self->{'_programs'}{$program}
            unless $self->{'_programs'}{$program} > 0;
    }

    $handle->push_write(
        'Subscription removed for : ' .
        join( ',', @programs )        .
        "\n"
    );
}

sub handle_fullfeed {
    my ( $self, $handle, $SID ) = @_;

    $self->remove_all_streams($SID);

    # FIXME: keep this inside the SID heap
    # FIXME: this does not add it anywhere to the streams heap
    $self->{'_full'}{$SID} = 1;
    $handle->push_write(
        "Full feed enabled, all other functions disabled.\n"
    );
}

sub handle_nofullfeed {
    my ( $self, $handle, $SID ) = @_;

    $self->remove_all_streams($SID);

    # XXX: Not in original implementation
    delete $self->{'_full'}{$SID};

    $handle->push_write("Full feed disabled.\n");
}

sub handle_match {
    my ( $self, $handle, $SID, $args ) = @_;

    $self->remove_stream( $SID, 'full' );

    my @words = map lc, split /[\s,]+/, $args;
    foreach my $word (@words) {
        $self->{'_words'}{$word}++;

        # FIXME: keep this inside the SID heap
        $self->{'_match'}{$SID}{$word} = 1;
    }

    $handle->push_write(
        'Receiving messages matching : ' .
        join( ', ', @words )             .
        "\n"
    );
}

sub handle_nomatch {
    my ( $self, $handle, $SID, $args ) = @_;

    my @words = map lc, split /[\s,]+/, $args;
    foreach my $word (@words) {
        delete $self->{'_match'}{$SID}{$word};

        # Remove the word from searching if this was the last client
        $self->{'_words'}{$word}--;
        delete $self->{'_words'}{$word}
            unless $self->{'_words'}{$word} > 0;
    }

    $handle->push_write(
        'No longer receiving messages matching : ' .
        join( ', ', @words )                       .
        "\n"
    );
}

sub handle_debug {
    my ( $self, $handle, $SID ) = @_;

    $self->remove_stream( $SID, 'full' );

    $self->{'_debug'}{$SID} = 1;
    $handle->push_write("Debugging enabled.\n");
}

sub handle_nobug {
    my ( $self, $handle, $SID ) = @_;

    $self->remove_stream( $SID, 'debug' );
    delete $self->{'_debug'}{$SID};
    $handle->push_write("Debugging disabled.\n");
}

sub handle_regex {
    my ( $self, $handle, $SID, $args ) = @_;

    $self->{'_full'}{$SID}
        and return;

    my $regex;
    eval {
        defined $args && length $args
            and $regex = qr{$args};
        1;
    } or do {
        my $error = $@ || 'Zombie error';

        $handle->push_write(
            "Invalid regular expression '$args', see: perldoc perlre\n"
        );

        return;
    };

    $self->{'_regex'}{$SID}{$regex} = 1;
    $handle->push_write(
        "Receiving messages matching regex : $args\n"
    );
}

sub handle_noregex {
    my ( $self, $handle, $SID ) = @_;

    $self->remove_stream( $SID, 'regex' );
    delete $self->{'_regex'}{$SID};
    $handle->push_write("No longer receiving regex-based matches\n");
}

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

    my $client_streams = delete $self->{'_streams'}{$stream}{$SID};

    # FIXME:
    # I *think* what this is supposed to do is delete assists
    # that were registered for this client, which it doesn't
    # - it deletes global assists instead - this needs to be
    # looked into
    if ($client_streams) {
        if ( my $assist = $_STREAM_ASSISTERS{$stream} ) {
            foreach my $key ( keys %{$client_streams} ) {
                --$self->{'_assists'}{$assist}{$key} <= 0
                    and delete $self->{'_assists'}{$assist}{$key}
            }
        }
    }
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
                my ( $hdl, $fatal, $msg ) = @_;
                my $SID = $inner_self->_gen_session_id($hdl);
                $inner_self->hangup_client($SID);
                $inner_self->_server_error( $msg, $fatal );
                $hdl->destroy;
            },

            on_eof => sub {
                my ($hdl) = @_;
                my $SID = $inner_self->_gen_session_id($hdl);
                $inner_self->hangup_client($SID);
                $hdl->destroy;
                AE::log debug => "SERVER, client $SID disconnected.";
            },

            # POE handler: client_input
            on_read => sub {
                my ($hdl) = @_;
                chomp( my $line = delete $hdl->{'rbuf'} );
                my $SID = $inner_self->_gen_session_id($hdl);

                foreach my $command ( keys %client_commands ) {
                    my $regex = $client_commands{$command};
                    if ( my ($args) = ( $line =~ /$regex/i ) ) {
                        my $method = "handle_$command";
                        return $inner_self->$method( $hdl, $SID, $args );
                    }
                }

                $hdl->push_write("UNKNOWN COMMAND, Ignored.\015\012");
            },
        );

        my $SID = $self->_gen_session_id($handle);
        $handle->push_write("EHLO Streamer (KERNEL: $$:$SID)\n");
        $inner_self->register_client( $SID, $handle );
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
    my ( $self, $SID, $handle ) = @_;

    # FIXME: put buffers in the client hash instead
    $self->{'_buffers'}{$SID} = [];

    $self->clients->{$SID} = {
        handle => $handle,
    };
}

sub _gen_session_id {
    my ( $self, $handle ) = @_;
    # AnyEvent::Handle=HASH(0x1bb30f0)
    "$handle" =~ /\D0x([a-fA-F0-9]+)/;
    return $1;
}

1;
