#!/usr/bin/perl

use strict;
use Bric::Lite;

use Data::Dumper;
use CGI;
use CGI::Cookie;
use CGI::Session ('-ip_match');
use HTTP::Cookies;
use SOAP::Lite;
use XML::LibXML;

my $cgi = new CGI;
my $session = new CGI::Session(undef, $cgi, {Directory=>'/tmp'});

if ($session->param('username')) {
    my $cookie_file = "/tmp/briclite-".$session->param('username').".cookie";
    unlink($cookie_file) if (-e $cookie_file);
}

$session->delete;
print $cgi->header(-location => 'index.cgi?logout=true');

