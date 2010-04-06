#!/usr/bin/perl

use strict;

use CGI;
use XML::LibXML;

my $cgi = new CGI;

print $cgi->header;

my $search = $cgi->param('q') || exit;
my @keywords;

my $parser = XML::LibXML->new;
my $xml = $parser->parse_file("keywords.xml");
my $root = $xml->getDocumentElement;

foreach my $keyword ($root->getElementsByLocalName('name')) {
    my $key = $keyword->textContent;
    push(@keywords, $key) if ($key =~ m/$search/i);
}

foreach (sort {lc($a) cmp lc($b)} @keywords) {
    print "$_\n";
}

