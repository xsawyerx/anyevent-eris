use t::lib::Eris::Test;

my ( $server, $cv ) = new_server;
my ( $addr, $port ) = @{$server}{qw<ListenAddress ListenPort>};
my $c = tcp_connect $addr, $port, sub {
    my ($fh) = @_
        or BAIL_OUT("Connect failed: $!");

    my $subscribed;
    my $hdl; $hdl = AnyEvent::Handle->new(
        fh       => $fh,
        on_error => sub { AE::log error => $_[2]; $_[0]->destroy },
        on_eof   => sub { $hdl->destroy; AE::log info => 'Done.' },
        on_read  => sub {
            my ($hdl) = @_;
            chomp( my $line = delete $hdl->{'rbuf'} );
            if ( !$subscribed ) {
                $hdl->push_write(
                    "subscribe prog1,prog2, prog3, prog4,prog5\n"
                );

                $subscribed++;
                return 1;
            } else {
                is(
                    $line,
                    'Subscribed to : prog1,prog2,prog3,prog4,prog5',
                    'Subscribed to all the right programs',
                );

                $cv->send('OK');
            }
        },
    );
};

is( $server->run($cv), 'OK', 'Server closed' );

is( $server->{'subscribers'}, undef, 'Subscribers cleared' );
is( $server->{'programs'},    undef, 'Programs cleared'    );

done_testing;
