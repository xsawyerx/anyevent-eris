use t::lib::Eris::Test;

my ( $server, $cv ) = new_server;
my ( $addr, $port ) = @{$server}{qw<ListenAddress ListenPort>};
my $c = tcp_connect $addr, $port, sub {
    my ($fh) = @_
        or BAIL_OUT("Connect failed: $!");

    my $hdl; $hdl = AnyEvent::Handle->new(
        fh       => $fh,
        on_error => sub { AE::log error => $_[2]; $_[0]->destroy },
        on_eof   => sub { $hdl->destroy; AE::log info => 'Done.' },
        on_read  => sub {
            my ($hdl) = @_;
            chomp( my $line = delete $hdl->{'rbuf'} );

            if ( $line =~ /^EHLO/ ) {
                $hdl->push_write(
                    "subscribe prog1,prog2, prog3, prog4,prog5\n"
                );

                is(
                    scalar keys %{ $server->{'subscribers'} },
                    0,
                    'No clients subscribed',
                );
            } elsif ( $line =~ /^Subscribed/ ) {
                is(
                    $line,
                    'Subscribed to : prog1,prog2,prog3,prog4,prog5',
                    'Subscribed to all the right programs',
                );

                is(
                    scalar keys %{ $server->{'subscribers'} },
                    1,
                    'A single client subscribed',
                );

                $hdl->push_write(
                    "unsubscribe prog1,prog2, prog3, prog4,prog5\n"
                );
            } else {
                $cv->send('OK');
            }
        },
    );
};

is( $server->run($cv), 'OK', 'Server closed' );

is_deeply( $server->{'subscribers'}, {}, 'Subscribers cleared' );
is_deeply( $server->{'programs'},    {}, 'Programs cleared'    );

done_testing;
