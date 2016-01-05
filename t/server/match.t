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

            my $words   = $server->{'words'};
            my $matches = $server->{'match'};
            if ( $line =~ /^EHLO/ ) {
                $hdl->push_write("match hello, world\n");

                is(
                    scalar keys %{$words},
                    0,
                    'No clients registered words',
                );

                is(
                    scalar keys %{$matches},
                    0,
                    'No clients registered matches',
                );
            } elsif ( $line =~ /^Receiving messages matching : / ) {
                is(
                    scalar keys %{$matches},
                    1,
                    'A single client has matches',
                );

                my $key = ( keys %{$matches} )[0];

                is_deeply(
                    $matches->{$key},
                    { hello => 1, world => 1 },
                    "$key registered for two words",
                );

                $hdl->push_write("nomatch hello, world\n");
            } elsif ( $line =~ /^No longer receiving messages matching : / ) {
                is(
                    scalar keys %{$words},
                    0,
                    'No more clients registered for words',
                );

                my $key = ( keys %{$matches} )[0];
                is(
                    scalar keys %{ $matches->{$key} },
                    0,
                    'No registered matches for client',
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
