#!/usr/bin/perl
use strict;
use warnings;
use AnyEvent;
use AnyEvent::eris::Server;

AE::log info => 'Starting Eris Server';

my $cv     = AE::cv;
my $server = AnyEvent::eris::Server->new();
$server->run($cv);
exit 0;
