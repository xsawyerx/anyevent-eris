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

            my $regex = $server->{'_regex'};
            if ( $line =~ /^EHLO/ ) {
                $hdl->push_write("regex .+\n");

                is(
                    scalar keys %{$regex},
                    0,
                    'No clients registered for regex',
                );
            } elsif ( $line =~ /^Receiving messages matching regex : / ) {
                is(
                    scalar keys %{$regex},
                    1,
                    'A single client has regex',
                );

                my $key = ( keys %{$regex} )[0];

                is(
                    scalar keys %{ $regex->{$key} },
                    1,
                    "$key registered for regex",
                );

                $hdl->push_write("noregex\n");
            } elsif ( $line =~ /^No longer receiving regex-based matches/ ) {
                is(
                    scalar keys %{$regex},
                    0,
                    'No more clients registered for regex',
                );

                $cv->send('OK');
            } else {
                $cv->send("Unknown response: $line");
            }
        },
    );
};

is( $server->run($cv), 'OK', 'Server closed' );

is( $server->{'subscribers'}, undef, 'Subscribers cleared' );
is( $server->{'programs'},    undef, 'Programs cleared'    );

done_testing;
