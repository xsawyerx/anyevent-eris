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

            my $debug = $server->{'debug'};
            if ( $line =~ /^EHLO/ ) {
                $hdl->push_write("debug\n");

                is(
                    scalar keys %{$debug},
                    0,
                    'No clients registered debugging',
                );
            } elsif ( $line =~ /^Debugging enabled/ ) {
                is(
                    scalar keys %{$debug},
                    1,
                    'A single client has debugging',
                );

                my $key = ( keys %{$debug} )[0];

                is(
                    $debug->{$key},
                    1,
                    "$key registered for debugging",
                );

                $hdl->push_write("nodebug\n");
            } elsif ( $line =~ /^Debugging disabled/ ) {
                is(
                    scalar keys %{$debug},
                    0,
                    'No more clients registered for debugging',
                );

                $cv->send('OK');
            } else {
                $cv->send("Unknown response: $line");
            }
        },
    );
};

is( $server->run($cv), 'OK', 'Server closed' );

done_testing;
