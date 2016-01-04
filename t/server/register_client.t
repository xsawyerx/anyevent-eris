use t::lib::Eris::Test;

my ( $server, $cv ) = new_server;
my ( $addr, $port ) = @{$server}{qw<ListenAddress ListenPort>};
my $c = tcp_connect $addr, $port, sub {
    my ($fh) = @_
        or BAIL_OUT("Connect failed: $!");

    my $hdl; $hdl = AnyEvent::Handle->new(
        fh       => $fh,
        on_connect => sub { print STDERR "Connected!\n" },
        on_error => sub { AE::log error => $_[2]; $_[0]->destroy },
        on_eof   => sub { $hdl->destroy; AE::log info => 'Done.' },
        on_read  => sub {
            my $hdl = shift;

            chomp( my $line = $hdl->rbuf );

            $line =~ /^EHLO Streamer \(KERNEL: (\d+):(\d+)\)$/;
            my $KID = $1 || '(undef)';
            my $SID = $2 || '(undef)';

            ok( $KID && $SID, "Got a nice hello (KID: $KID, SID: $SID)" );
            $cv->send('OK');
        },
    );
};

is( $server->run($cv), 'OK', 'Server closed' );

done_testing;
