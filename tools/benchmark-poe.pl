#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Test::MemoryGrowth;
use Time::HiRes;
use POE qw(
   Component::Server::TCP
   Component::Server::eris
   Component::Client::eris
);

# test parameters
my $msg_count = 1e4;
my $MSG       = '<11>Jan  1 00:00:00 zmainfw snort[32640]: [1:1893:4] SNMP missing community string attempt [Classification: Misc Attack] [Priority: 2]: {UDP} 1.2.3.4:23210 -> 5.6.7.8:161';

# memory growth check
my $mem_calls   = 2;
my $mem_burn_in = 2;

no_growth {

my $chunk_count = 0;

# Message Dispatch Service
my $SERVER_SESSION = POE::Component::Server::eris->spawn();

my ( $now, $later );
my $ERIS_SESSION_ID = POE::Component::Client::eris->spawn(
    Subscribe      => [qw<fullfeed>],
    MessageHandler => sub {
        $chunk_count++;

        if ( $_[0]->{'content'} =~ /end/ ) {
            $later = Time::HiRes::time();
            $POE::Kernel::poe_kernel->stop;
        }
    },
);

POE::Session->create(
    inline_states => {
        _start => sub {
            $_[KERNEL]->delay( next => 1.5 );
        },

        next => sub {
            $now = Time::HiRes::time();
            for ( 1 .. $msg_count ) {
                # An event will post incoming messages to:
                $_[KERNEL]->post(
                    eris_dispatch => dispatch_message => $MSG
                );
            }

            $_[KERNEL]->post(
                eris_dispatch => dispatch_message => 'end'
            );
        },
    },
);

POE::Kernel->run();

printf "Processed %d msgs (in %d chunks) in %.5f seconds\n",
       $msg_count + 1, $chunk_count, $later - $now;

} calls => $mem_calls, burn_in => $mem_burn_in, 'No memory leak detected!';

done_testing;
