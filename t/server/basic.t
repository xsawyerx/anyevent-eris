use t::lib::Eris::Test;

subtest 'Spawning' => sub {
    my $server = AnyEvent::eris::Server->new();
    isa_ok( $server, 'AnyEvent::eris::Server' );
};

subtest 'Run server' => sub {
    my ( $server, $cv ) = new_server;
    can_ok( $server, 'run' );
    my $t; $t = AE::timer 0, 0, sub {
        undef $t;
        $cv->send('OK');
    };

    is( $server->run($cv), 'OK', 'Server closed' );
};

done_testing;
