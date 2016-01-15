#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Test::MemoryGrowth;
use AnyEvent;
use AnyEvent::eris::Client;
use AnyEvent::eris::Server;

# test parameters
my $msg_count = 1e4;
my $MSG       = '<11>Jan  1 00:00:00 zmainfw snort[32640]: [1:1893:4] SNMP missing community string attempt [Classification: Misc Attack] [Priority: 2]: {UDP} 1.2.3.4:23210 -> 5.6.7.8:161';

# memory growth check
my $mem_calls   = 2;
my $mem_burn_in = 2;

no_growth {

my $cv          = AE::cv;
my $chunk_count = 0;

my $later;
my $server = AnyEvent::eris::Server->new();
my $client; $client = AnyEvent::eris::Client->new(
    Subscribe      => [qw<fullfeed>],
    MessageHandler => sub {
        $chunk_count++;

        if ( $_[0]->{'content'} =~ /end/ ) {
            $later = AE::now;
            $cv->send;
        }
    },
);

my $now;
my $t; $t = AE::timer 1, 0, sub {
    undef $t;
    $now = AE::now;
    for ( 1 .. $msg_count ) {
        $server->dispatch_message($MSG);
    }

    $server->dispatch_message('end');
};

$server->run($cv);

printf STDERR "Processed %d msgs (in %d chunks) in %.5f seconds\n",
       $msg_count + 1, $chunk_count, $later - $now;

} calls => $mem_calls, burn_in => $mem_burn_in, 'No memory leak detected!';

done_testing;
