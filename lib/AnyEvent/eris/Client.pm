package AnyEvent::eris::Client;
use strict;
use warnings;
use Carp;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use List::Util;
use Scalar::Util;
use Parse::Syslog::Line 'parse_syslog_line';

sub new {
    my ( $class, %opts ) = @_;

    my $self = bless {
        RemoteAddress  => '127.0.0.1',
        RemotePort     => 9514,
        ReturnType     => 'hash',
        Subscribe      => undef,
        Match          => undef,
        MessageHandler => undef,
        %opts,
    }, $class;

    $opts{'MessageHandler'}
        or AE::log fatal => 'You must provide a MessageHandler';

    ref $opts{'MessageHandler'} eq 'CODE'
        or AE::log fatal => 'You need to specify a subroutine reference to the \'MessageHandler\' parameter.';

    $self->_connect;

    return $self;
}

sub _connect {
    my $self = shift;

    my $block           = $self->{'ReturnType'} eq 'block';
    my $separator       = $block ? "\n" : '';
    my ( $addr, $port ) = @{$self}{qw<RemoteAddress RemotePort>};

    # FIXME: TODO item for this
    $block
        and AE::log fatal => 'Block option not supported yet';

    Scalar::Util::weaken( my $inner_self = $self );

    $self->{'_client'} ||= tcp_connect $addr, $port, sub {
        my ($fh) = @_
            or AE::log fatal => "Connect failed: $!";

        my $hdl; $hdl = AnyEvent::Handle->new(
            fh       => $fh,
            on_error => sub {
                AE::log error => $_[2];
                $_[0]->destroy;
                $inner_self->{'_reconnect_timer'} = AE::timer 10, 0, sub {
                    undef $inner_self->{'_reconnect_timer'};
                    $inner_self->_connect;
                };
            },

            on_eof   => sub { $hdl->destroy; AE::log info => 'Done.' },

            on_read  => sub {
                my ($hdl) = @_;
                # XXX: we currently do not allow $block to be set
                # all lines have a newline at the end
                # original code:
                # chomp $line unless $block
                chomp( my $line = delete $hdl->{'rbuf'} );

                if ( $inner_self->{'readyState'} == 1 ) {
                    $inner_self->handle_message( $line, $hdl ); 
                    return;
                }

                if ( $inner_self->{'connected'} == 1 ) {
                    if ( $line =~ /^Subscribed to :/ ) {
                        $inner_self->{'readyState'} = 1;
                    } elsif ( $line =~ /^Receiving / ) {
                        $inner_self->{'readyState'} = 1;
                    } elsif ( $line =~ /^Full feed enabled/ ) {
                        $inner_self->{'readyState'} = 1;
                    } else {
                        $inner_self->handle_unknown($line);
                    }
                } elsif ( $line =~ /^EHLO Streamer/ ) {
                    $inner_self->{'connected'} = 1;
                } else {
                    $inner_self->handle_unknown($line);
                }
            },
        );

        $inner_self->{'readyState'}        = 0;
        $inner_self->{'connected'}         = 0;
        $inner_self->{'buffer'}            = '';
        $inner_self->{'_setup_pipe_timer'} = AE::timer 1, 0, sub {
            undef $inner_self->{'_setup_pipe_timer'};
            $inner_self->setup_pipe($hdl);
        };
    };

    return $self;
}

sub setup_pipe {
    my ( $self, $handle ) = @_;

    # Parse for Subscriptions or Matches
    my %data;
    foreach my $target (qw(Subscribe Match)) {
        if ( exists $self->{$target} && defined $self->{$target} ) {
            my @data = ref $self->{$target} eq 'ARRAY'
                     ? @{ $self->{$target} }
                     : $self->{$target};

            @data = map lc, @data if $target eq 'Subscribe';
            next unless scalar @data > 0;
            $data{$target} = \@data;
        }
    }

    # Check to make sure we're doing something
    keys %data
        or AE::log fatal => 'Must specify a subscription or a match parameters!';

    # Send the Subscription
    foreach my $target ( sort keys %data ) {
        my $subname = 'do_' . lc $target;
        $self->$subname( $handle, $data{$target} );
    }
}

sub do_subscribe {
    my ( $self, $handle, $subs ) = @_;

    if ( List::Util::first { $_ eq 'fullfeed' } @{$subs} ) {
        $handle->push_write("fullfeed\n");
    } else {
        $handle->push_write(
            'sub '                 .
            join( ', ', @{$subs} ) .
            "\n"
        );
    }
}

sub do_match {
    my ( $self, $handle, $matches ) = @_;
    $handle->push_write(
        'match '                  .
        join( ', ', @{$matches} ) .
        "\n"
    );
}

sub handle_message {
    my ( $self, $line, $handle ) = @_;

    my $msg;
    if( $self->{'ReturnType'} eq 'string' ) {
        $msg = $line;
    } elsif( $self->{'ReturnType'} eq 'block' ) {
        my $index = rindex $line, "\n";

        if ( $index == -1 ) {
            $self->{'buffer'} .= $line;
            return;
        } else {
            $msg = $self->{'buffer'} . substr $line, 0, $index + 1;
            $line->{'buffer'} = substr $line, $index + 1;
        }
    } else {
        my $success = eval {
            no warnings;
            $msg = parse_syslog_line($line);
            1;
        };

        $success && $msg
            or return;
    }

    # Try the Message Handler, eventually we can do statistics here.
    eval {
        $self->{'MessageHandler'}->($msg);
        1;
    } or do {
        my $error = $@ || 'Zombie error';
        AE::log error => "MessageHandler failed: $error";
    };
}

1;
