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
                $hdl->push_write("fullfeed\n");

                is(
                    scalar keys %{ $server->{'full'} },
                    0,
                    'No clients have fullfeed',
                );
            } elsif ( $line =~ /^Full feed enabled/ ) {
                is(
                    scalar keys %{ $server->{'full'} },
                    1,
                    'A single client has fullfeed',
                );

                my $key = ( keys %{ $server->{'full'} } )[0];
                is(
                    $server->{'full'}{$key},
                    1,
                    "$key registered for fullfeed true",
                );

                $hdl->push_write("nofullfeed\n");
            } elsif ( $line =~ /^Full feed disabled/ ) {
                is(
                    scalar keys %{ $server->{'full'} },
                    0,
                    'No more clients registered for fullfeed',
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
