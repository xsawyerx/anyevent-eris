package t::lib::Eris::Test;

use strict;
use warnings;
use Test::More       ();
use AnyEvent         ();
use AnyEvent::Handle ();
use AnyEvent::Socket ();
use Import::Into     ();
use Net::EmptyPort   ();

BEGIN {
    Test::More::use_ok('AnyEvent::eris::Client');
    Test::More::use_ok('AnyEvent::eris::Server');
}

sub import {
    my $target = caller;
    strict->import::into($target);
    warnings->import::into($target);
    Test::More->import::into($target);
    AnyEvent->import::into($target);
    AnyEvent::Socket->import::into($target);
    AnyEvent::Handle->import::into($target);
    {
        no strict 'refs'; ## no critic
        *{"${target}::new_server"} = *new_server;
    }
}

sub new_server {
    my $cv     = AE::cv;
    my $server = AnyEvent::eris::Server->new(
        ListenPort => $ENV{'ERIS_TEST_PORT'} ||
                      Net::EmptyPort::empty_port(),
    );

    return ( $server, $cv );
}

1;
