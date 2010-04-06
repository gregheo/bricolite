#!/usr/bin/perl

use strict;

use CGI;
use CGI::Cookie;
use CGI::Session ('-ip_match');
use BricLite;
use Data::Dumper;

my $cgi = new CGI;

if (!$cgi->param('username')) {
    print $cgi->header(-location => 'index.cgi?error=true');
    exit;
}

my $briclite = new BricLite;
my $userdata;

eval {
    $userdata = $briclite->login($cgi->param('username'),
        $cgi->param('password'),
        sub {
            my ($soap, $res) = @_;
            die (ref $res ? $res->faultdetail : $soap->transport->status);
        });
1; };

if (!$userdata || $@) {
    $briclite->logmessage("$@ login failed for username ".$cgi->param('username'));
    print $cgi->header(-location => 'index.cgi?error=true&username='.$cgi->param('username'));
    exit;
}

$briclite->logmessage("login succeeded for username ".$cgi->param('username'));

my $session = new CGI::Session("driver:File", undef, {Directory=>"/tmp"});
$session->param('username', $cgi->param('username'));
while (my ($key, $value) = each(%{$userdata})) {
    $session->param($key, $value);
}
my $cookie = new CGI::Cookie(-name=>'CGISESSID', -value=>$session->id);
print $cgi->header(-cookie => $cookie, -location => 'home.cgi');


=pod

my $session = $briclite->login($cgi->param('username'), $cgi->param('password'));

if (!$session) {
    print $cgi->header(-location => 'index.cgi?error=true&username='.$cgi->param('username'));
    exit;
}

my $cookie = new CGI::Cookie(-name=>'CGISESSID', -value=>$session->id);
#print $cgi->header(-cookie=>$cookie, -location => 'home.cgi');
print $cgi->header(-cookie=>$cookie);
print "session id is: ".$session->id;
print Dumper($session);

=cut

