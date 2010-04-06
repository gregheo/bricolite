package Bric::Lite;

use strict;

use CGI;
use CGI::Cookie;
use CGI::Session ('-ip_match');
use Data::Dumper;
use DateTime;
use Encode;
use HTML::Entities;
use HTTP::Cookies;
use SOAP::Lite (on_fault => \&_handle_fault);
use SOAP::Lite;
use XML::LibXML;

import SOAP::Data 'name';

use vars qw($VERSION);
$VERSION = '1.00';

################################# configuration ##############################

# Maximum slug length for auto-generated slugs.
# Note: This is a fuzzy maximum, not an absolute one; The actual length will
# depend on the word breaks.
use constant MAX_SLUG_LENGTH => 20;

# How latest is "latest" for "latest posts"?? Measured in number of days.
use constant HOW_LATEST => 20;

# bricolage variables: URL, site name, output channel
use constant BRIC_SOAP_URL => "http://phantom.node79.com:8001/soap";
use constant BRIC_SITE => "Default Site";
use constant BRIC_OC => "Web";

# story element name
use constant STORY_ELEMENT => 'story';

# if set, "publish" will actually publish
# if unset, "publish" will just check in and move to the publish desk
use constant REALLY_PUBLISH => 0;

# publish desk name
use constant PUBLISH_DESK => 'Publish';

use constant SOURCE_NAME => 'Internal';

# log file
# set to blank string to disable logging
use constant LOG_FILE => '/usr/local/www/log/bricolite.log';

# categories
use constant CATEGORIES => qw/1/;

# temp directory to store cookie files
use constant COOKIE_DIR => '/tmp';

############################### end configuration ############################



my $soap;
my $session_data;

sub new
{
    my $package = shift;
    $session_data = shift;

    if (ref($session_data) eq 'HASH') {
        init_soap($package, $session_data->{'login'});
    }

    return bless({}, $package);
}

sub init_soap
{
    my $self = shift;
    my $username = shift;
    my $on_fault = shift;

    my $verbose = 999;
    my $timeout = 300;

    $soap = new SOAP::Lite
        uri      => 'http://bricolage.sourceforge.net/Bric/SOAP/Auth',
        on_fault => ($on_fault ? $on_fault : \&_handle_fault),
        readable => $verbose > 2 || 0;
    my $cookie_string = COOKIE_DIR."/briclite-".$username.".cookie";
        
    $soap->proxy(BRIC_SOAP_URL,
                 cookie_jar => HTTP::Cookies->new(ignore_discard => 1,
                     file => $cookie_string,
                     autosave => 1),
                 timeout => $timeout,
    );  

}

sub login
{
    my $self = shift;
    my $username = shift;
    my $password = shift;
    my $on_fault = shift;

    init_soap($self, $username, $on_fault);

    my $response = $soap->login(name(username => $username), name(password => $password));
    if ($response->fault) {
        return 0;
    }

    # call up user id
    $soap->uri('http://bricolage.sourceforge.net/Bric/SOAP/User');
    my %search = ( login => $username );
    my $stat = $soap->list_ids(map { name($_ => $search{$_}) }
                               keys %search);
    my ($count, $data, $user_id);
    for ($count = 1; $data = $stat->dataof("/Envelope/Body/[1]/[1]/[$count]"); $count++) {
        $user_id = $data->value;
    }

    # call up user data
    my @opts;
    my @ids;
    push @ids, $user_id;
    push @opts, name('user_ids', \@ids);
    my $user_xml = $soap->export(@opts)->result;



    my %userdata;
    $userdata{'username'} = $username;
    $userdata{'user_id'} = $user_id;
    $userdata{'user_xml'} = $user_xml;
    my $parser = XML::LibXML->new;
    my $doc = $parser->parse_string($user_xml);
    my $root = $doc->getDocumentElement;

    foreach my $user ($root->getChildrenByTagName('user')) {
        foreach my $child ($user->childNodes) {
            my $nodename = $child->nodeName;
            $userdata{"$nodename"} = $child->textContent;
        }
    }

    return \%userdata;

}


sub get_categories {
    my $self = shift;

    my %categories;
    my $parser = XML::LibXML->new;

    # silence errors temporarily
    init_soap($self, $session_data->{'login'}, sub{my($soap, $res) = @_;die;});

    $soap->uri('http://bricolage.sourceforge.net/Bric/SOAP/Category');

    # loop through all category IDs to check permisions
    foreach my $category (CATEGORIES) {
        my $cat_xml;
        eval {
            my @opts;
            push(@opts, name('category_ids', [$category]));
            $cat_xml = $soap->export(@opts)->result;
        1; };
        if (!$@) {
            my $doc = $parser->parse_string($cat_xml);
            my $root = $doc->getDocumentElement;
            foreach my $node ($root->getChildrenByTagName('category') ) {
                my ($path, $name);
                foreach my $child ($node->childNodes) {
                    $name = $child->textContent if ($child->nodeName eq 'name');
                    $path = $child->textContent if ($child->nodeName eq 'path');
                }
                $categories{"$path"} = $name;
            }
        } else { print "$@ BAD!!!"; }
    }

    # restore usual error handling
    init_soap($self, $session_data->{'login'});

    return \%categories;
}

sub get_categories_xml {
    my $self = shift;

    $soap->uri('http://bricolage.sourceforge.net/Bric/SOAP/Category');
    my %search = ( site => BRIC_SITE );
    my $stat = $soap->list_ids(map { name($_ => $search{$_}) } keys %search);
    my ($count, $data, @cat_ids);
    for ($count = 1; $data = $stat->dataof("/Envelope/Body/[1]/[1]/[$count]"); $count++) {
        push(@cat_ids, $data->value);
    }

    my @opts;
    push(@opts, name('category_ids', \@cat_ids));
    my $cat_xml = $soap->export(@opts)->result;

    return $cat_xml;
}

sub get_latest_posts_xml {
    my $self = shift;

    $soap->uri('http://bricolage.sourceforge.net/Bric/SOAP/Story');
    my $cover_date_start = DateTime->now->subtract( days => HOW_LATEST );
    my %search = ( element_key_name => STORY_ELEMENT,
                   description => '%'._process_text($session_data->{'fname'}.' '.$session_data->{'lname'}).'%',
                   site => BRIC_SITE,
                   active => 1,
                   unexpired => 1,
                   cover_date_start => $cover_date_start->strftime('%FT%TZ')
               );

    my $stat = $soap->list_ids(map { name($_ => $search{$_}) } keys %search);

    return "<assets/>" if (!$stat);

    my ($count, $data, @story_ids);
    for ($count = 1; $data = $stat->dataof("/Envelope/Body/[1]/[1]/[$count]"); $count++) {
        push(@story_ids, $data->value);
    }

    # cheap way to get descending sort
    @story_ids = reverse(@story_ids);

    my @opts;
    push(@opts, name('story_ids', \@story_ids));
    my $story_xml = $soap->export(@opts)->result;

    return $story_xml;
}


sub save_and_publish_story
{
    my $self = shift;
    my $data = shift;

    my $story_id = save_story($self, $data);
    if ($story_id) {
        return publish_story($self, $story_id);
    } else {
        return 0;
    }
}

sub publish_story
{
    my $self = shift;
    my $story_id = shift;

    return if (!$story_id);

    my $stat = _checkin_publish($self, $story_id);

    return 0 if ($stat != $story_id);

    if (REALLY_PUBLISH) {
        return _really_publish($self, $story_id);
    } else {
        return $stat;
    }
}


sub _really_publish
{
    my $self = shift;
    my $story_id = shift;

    $soap->uri('http://bricolage.sourceforge.net/Bric/SOAP/Workflow');

    my @story_ids = (name("story_id", $story_id));
    my @opts;
    my $stat = $soap->publish(name(publish_ids => \@story_ids), @opts);

    my @id = _get_result_ids($self, $stat);
    my $ret_story_id = $id[0];

    return $ret_story_id;
}

sub _checkin_publish
{
    my $self = shift;
    my $story_id = shift;

    $soap->uri('http://bricolage.sourceforge.net/Bric/SOAP/Workflow');

    my @story_ids = (name("story_id", $story_id));
    my @opts = (name(desk => PUBLISH_DESK));
    my $stat = $soap->move(name(move_ids => \@story_ids), @opts);

    my @id = _get_result_ids($self, $stat);
    my $ret_story_id = $id[0];

    return $ret_story_id;
}

sub save_story
{
    my $self = shift;
    my $data = shift;

    my $story_xml = _make_story_xml($self, $data);
    logmessage(1, "story_xml:\n$story_xml\n");

    my @opts;
    $soap->uri('http://bricolage.sourceforge.net/Bric/SOAP/Story');

    my $stat;
    if ($data->{'story_id'}) {
        my @update_ids;
        push @update_ids, $data->{'story_id'};
        $stat = $soap->update(name(document => $story_xml)->type('base64'), name(update_ids =>[ map { name('story_id' => $_) } @update_ids ]), @opts);
    } else {
        $stat = $soap->create(name(document => $story_xml)->type('base64'), @opts);
    }

    my @id = _get_result_ids($self, $stat);
    my $story_id = $id[0];

    return $story_id;
}

sub get_story_xml
{
    my $self = shift;
    my $story_id = shift;

    my @export_opts;
    my @ids;
    push @ids, $story_id;
    push @export_opts, name('story_ids', \@ids);
    $soap->uri('http://bricolage.sourceforge.net/Bric/SOAP/Story');
    my $story_xml = $soap->export(@export_opts)->result;
    return $story_xml;
}


sub make_slug
{
    my $self = shift;
    my $title = shift;

    my $slug = lc($title);
    $slug =~ s/[^\d\w]/-/g;
    $slug =~ s/-+/-/g;
    if (length($slug) > MAX_SLUG_LENGTH) {
        $slug = substr($slug, 0, index($slug, '-', MAX_SLUG_LENGTH));
    }
    $slug =~ s/-$//g;

    return $slug;
}


sub logmessage
{
    my $self = shift;
    my $message = shift;

    return if (!LOG_FILE);

    my $dt = DateTime->now;

    open(LOG, ">>".LOG_FILE);
    print LOG $dt->ymd, "T", $dt->hms," -- $message\n";
    close(LOG);

    return $message;
}


sub _make_story_xml {
    my $self = shift;
    my $data = shift;

    if ($data->{'story_id'}) {
        return _make_update_story_xml($self, $data);
    } else {
        return _make_create_story_xml($self, $data);
    }
}


sub _make_update_story_xml
{
    my $self = shift;
    my $data = shift;

    my $story_xml = $data->{'story_xml'};
    my $parser = XML::LibXML->new;
    my $xml = $parser->parse_string($story_xml);
    my $root = $xml->getDocumentElement;

    # update title, slug, category, cover date
    _xml_update_element_text(@{$root->getElementsByLocalName('name')}[0], $data->{'name'});
    _xml_update_element_text(@{$root->getElementsByLocalName('slug')}[0], $data->{'slug'});
    _xml_update_element_text(@{$root->getElementsByLocalName('category')}[0], @{$data->{"categories"}}[0]);
    _xml_update_element_text(@{$root->getElementsByLocalName('cover_date')}[0], $data->{"cover_date"});

    # contributor information
    _xml_update_element_text(@{$root->getElementsByLocalName('description')}[0], "bricolite blog post from ".$data->{'fname'}." ".$data->{'lname'});
    my $have_contributor = 0;
    foreach my $contributor ($root->getElementsByLocalName('contributor')) {
        if (@{$contributor->getElementsByLocalName('fname')}[0]->textContent eq $data->{'fname'} && @{$contributor->getElementsByLocalName('lname')}[0]->textContent eq $data->{'lname'}) {
            $have_contributor = 1;
        }
    }
    if (!$have_contributor) {
        my $item = @{$root->getElementsByLocalName('contributors')}[0];
        my $con = $xml->createElement('contributor');
        foreach my $tag ('fname', 'mname', 'lname', 'type', 'role') {
            my $element = $xml->createElement($tag);
            $element->appendChild(XML::LibXML::CDATASection->new(_process_text($data->{$tag})));
            $con->appendChild($element);
        }
        $item->appendChild($con);
    }
    
    # text fields
    foreach my $field ($root->getElementsByLocalName('field')) {
        if ($field->getAttribute('type') eq 'deck') {
            _xml_update_element_text($field, $data->{'deck'});
        }
    }

    return $xml->toString(1);
}



sub _make_create_story_xml
{
    my $self = shift;
    my $data = shift;

    my $xml = XML::LibXML::Document->new('1.0', 'UTF-8');
    my $root = $xml->createElement('assets');
    $xml->setDocumentElement($root);
    $root->setAttribute("xmlns", "http://bricolage.sourceforge.net/assets.xsd");
    my $story = $xml->createElement('story');
    $story->setAttribute("element_type", STORY_ELEMENT);
    $story->setAttribute("story_id", $data->{'story_id'}) if ($data->{'story_id'});
    $story->setAttribute("uuid", $data->{'uuid'}) if ($data->{'uuid'});
    $root->appendChild($story);

    my %boilerplate = (
        site => BRIC_SITE,
        priority => 3,
        publish_status => 0,
        active => 1,
        source => SOURCE_NAME
    );

    my @from_param = (
        'name', 'slug', 'cover_date'
    );

    foreach my $key (keys(%boilerplate)) {
        my $item = $xml->createElement($key);
        $item->appendChild(XML::LibXML::Text->new($boilerplate{$key}));
        $story->appendChild($item)
    }

    if (!$data->{"cover_date"}) {
        my $dt = DateTime->now;
        $data->{"cover_date"} = $dt->strftime('%FT%TZ');
    }

    foreach my $key (@from_param) {
        my $item = $xml->createElement($key);
        $item->appendChild(XML::LibXML::CDATASection->new(_process_text($data->{$key})));
        $story->appendChild($item)
    }

    # Categories
    {
        my $item = $xml->createElement('categories');
        my $first = 0;
        foreach my $category (@{$data->{"categories"}}) {
            my $cat = $xml->createElement('category');
            $cat->appendChild(XML::LibXML::Text->new($category));
            $cat->setAttribute('primary', '1') if ($first++==0);
            $item->appendChild($cat);
        }
        $story->appendChild($item);
    }

    # Contributors + description tag
    {
        my $item = $xml->createElement('contributors');
        my $con = $xml->createElement('contributor');
        foreach my $tag ('fname', 'mname', 'lname', 'type', 'role') {
            my $element = $xml->createElement($tag);
            $element->appendChild(XML::LibXML::CDATASection->new(_process_text($data->{$tag})));
            $con->appendChild($element);
        }
        $item->appendChild($con);
        $story->appendChild($item);
    }
    {
        my $item = $xml->createElement('description');
        $item->appendChild(XML::LibXML::CDATASection->new(_process_text("bricolite blog post from ".$data->{'fname'}." ".$data->{'lname'})));
        $story->appendChild($item);
    }

    # Output channel
    {
        my $item = $xml->createElement('output_channels');

        my $oc = $xml->createElement('output_channel');
        $oc->appendChild(XML::LibXML::Text->new(BRIC_OC));
        $oc->setAttribute('primary', '1');
        $item->appendChild($oc);

        $story->appendChild($item);
    }

    # the real data!
    my $elements = $xml->createElement('elements');

    my $deck = $xml->createElement('field');
    $deck->setAttribute('order', '2');
    $deck->setAttribute('type', 'deck');
    $deck->appendChild(XML::LibXML::CDATASection->new(_process_text($data->{deck})));

    $elements->appendChild($deck);
    $story->appendChild($elements);

    #print "\n<!--\n".$xml->toString(1)."\n-->\n";
    return $xml->toString(1);
}

sub _process_text {
    my $text = shift;

    $text = Encode::decode('iso-8859-1', $text);
    
    return $text;
}

sub _get_result_ids {
    my $self = shift;
    my $response = shift;

    my @return;

    # print out ids with types
    my ($count, $data);
    for ($count = 1; $data = $response->dataof("/Envelope/Body/[1]/[1]/[$count]"); $count++) {
        push(@return, $data->value);
    }

    return @return;
}

sub _xml_update_element_text
{
    my $element = shift;
    my $text = shift;

    # special fix for non-breaking space and WYMeditor
    $text =~ s/\xa0/&nbsp;/g;

    $element->removeChild($element->lastChild) if $element->lastChild;
    $element->appendChild(XML::LibXML::CDATASection->new(_process_text($text)));
}


sub _handle_fault {
    my ($soap, $r) = @_;

    # print out the error as appropriate
    if (ref $r) {
        if ($r->faultstring eq 'Application error' and
            ref $r->faultdetail and ref $r->faultdetail eq 'HASH'    ) {
            # this is a bric exception, the interesting stuff is in detail
            logmessage(1, "Bricolage SOAP fault: ".Dumper($soap).Dumper($r->faultdetail));
            #print ("Bricolage SOAP fault: ", join("\n", values %{$r->faultdetail}), $/, $/);
        } else {
            logmessage(1, "Bricolage SOAP fault: ".Dumper($soap).Dumper($r));
            print ("Bricolage SOAP fault: ", $r->faultstring);
        }
    } else {
        logmessage(1, "Bricolage SOAP fault: ".Dumper($soap).Dumper($r));
        print ("SOAP transport error: ", $soap->transport->status);
    }
    die;
}


1;
__END__

=pod

=head1 NAME

Bric::Lite - A light Perl interface to a remote Bricolage/SOAP server

=head1 SYNOPSIS

    use Bric::Lite;
    my $briclite = new Bric::Lite;

=head1 DESCRIPTION

Bric/Lite.pm is part of the 'Bricolite' distribution, a simplified user
interface to Bricolage. Bricolite was originally developed to make things
easier for bloggers by presenting them with a basic feature set: view recent
posts, add/edit posts, rich-text editor, etc.

The goal of Bric/Lite.pm is to wrap the server-to-server communication and
to provide simple entry points into Bricolage. The front-end pages are
Perl CGI.

This code is meant as a starting point rather than an out-of-the-box solution,
as Bricolage installations are by nature very different from each other
(story types and elements, output channels, use of keywords, contributors,
permissions, etc.) This code as-distributed should work on a stock Bricolage
install as it only references the root category and the "story" element type.

A very helpful screencast is here, courtesy of Phillip Smith:
L<http://screencast.com/t/qdmwtvjlaz>

=head1 CUSTOMIZING TO YOUR INSTALLATION

=over

=item * Constants at the top of this file.

=item * C<_make_update_story_xml> and C<_make_create_story_xml> methods.

=item * Most of post.cgi to match your own element definition.

=back

=head1 WARNINGS

=over

=item * category permissions

=item * contributors

=item * error handling (or lack of)

=item * text encoding

=back

=head1 TO-DO

=over

=item * Better documentation

=item * Tests!

=back

=head1 CREDITS

Code by Greg Heo, copiously cribbed from Bricolage itself. Errors and general
code ugliness are all my own though. Released under the same licence as
Bricolage itself.

UI styling (HTML, CSS, images) by Phillip Smith.

Initial concept by Phillip Smith and the fine folks at New Internationalist
Publications (L<http://www.newint.org/>)


=cut

