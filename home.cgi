#!/usr/bin/perl

use strict;
use BricLite;
use CGI;
use CGI::Session ('-ip_match');
use Data::Dumper;
use DateTime;
use XML::LibXML;

my $cgi = new CGI;
my $session = new CGI::Session(undef, $cgi, {Directory=>'/tmp'});

if (!$session->param('username')) {
    print $cgi->header(-location => 'index.cgi');
    exit;
}

my $briclite = new BricLite($session->param_hashref);

print $session->header;
print $cgi->start_html(-title => 'bricolite - Your latest blog posts',
					   -class=>'home',
                       -style => { -src => 'briclite.css' },
                       -script => [ {-language => 'JavaScript', -src=>'jquery/jquery.js'}]);

my $fname = $session->param("fname");

print <<EOT;
<div id="content">

<p><strong>Hello, $fname</strong>!</p>

<p><a href="post.cgi">Add a new post</a></p>

<p>Your latest posts:</p>
<ul>

EOT

my $parser = XML::LibXML->new;
my $doc = $parser->parse_string($briclite->get_latest_posts_xml);
my $root = $doc->getDocumentElement;

foreach my $story ($root->getChildrenByTagName('story')) {
    my ($name, $id, $cover_date);
    $id = $story->findvalue('./@id');
    foreach my $child ($story->childNodes) {
        $name = $child->textContent if ($child->nodeName eq 'name');
        $cover_date = $child->textContent if ($child->nodeName eq 'cover_date');
    }
    my $dt = DateTime->new( year => substr($cover_date, 0, 4),
                            month => substr($cover_date, 5, 2),
                            day => substr($cover_date, 8, 2),
                            hour => substr($cover_date, 11, 2),
                            minute => substr($cover_date, 14, 2),
                            second => substr($cover_date, 17, 2));

    print "<li><a href='post.cgi?story_id=$id'>$name (".$dt->strftime('%e %B %Y, %H:%M GMT').")</a></li>";
}

print "</ul>";

print "<p><a href='logout.cgi'>Log out</a></p>";
print "</div>";
print $cgi->end_html;

