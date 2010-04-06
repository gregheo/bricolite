#!/usr/bin/perl

use strict;
use BricLite;
use Encode;
use XML::LibXML;
use Data::Dumper;
use MIME::Base64 ();

use CGI;
use CGI::Session ('-ip_match');

my $cgi = new CGI;
my $session = new CGI::Session(undef, $cgi, {Directory=>'/tmp'});

if (!$session->param('username')) {
    print $cgi->header(-location => 'index.cgi');
    exit;
}

my $briclite = new BricLite($session->param_hashref);

#print $session->header(-type=>'text/html', -charset=>'utf-8');
print $session->header();


print $cgi->start_html(
            -title => 'bricolite - Add new blog post',
                       -style => { -src => [ 'jquery/jquery.suggest.css',
                                             'briclite.css' ] },
					   -class=>'post',
                       -script => [ {-language => 'JavaScript', -src=>'jquery/jquery.js'},
                                    {-language => 'JavaScript', -src=>'jquery/jquery.dimensions.js'},
                                    {-language => 'JavaScript', -src=>'jquery/jquery.bgiframe.js'},
                                    {-language => 'JavaScript', -src=>'jquery/jquery.suggest.js'},
                                    {-language => 'JavaScript', -src=>'jquery/jquery.ui.js'},
                                    {-language => 'JavaScript', -src=>'wymeditor/jquery.wymeditor.pack.js'},
                                    ]
                                );


print '<div id="content">';                                 
print "<p><strong>Hello, ".$session->param("fname")."!</strong></p>";

my $story_id = $cgi->param('story_id');
my ($cover_year, $cover_month, $cover_day, $cover_hour, $cover_minute);

if ($cgi->param('submit') || $cgi->param('publish')) {
    my %data = $cgi->Vars;
    # fix multiple select items
    my @categories = $cgi->param("categories");
    $data{"categories"} = \@categories;
    my @keywords = $cgi->param("keywords");
    $data{"keywords"} = \@keywords;
    my @teams = $cgi->param("teams");
    $data{"teams"} = \@teams;
    $data{'keywords_flat'} = '';

    $data{"cover_date"} = $data{'cover_year'}.'-'.$data{'cover_month'}.'-'.$data{'cover_day'}.'T'.$data{'cover_hour'}.':'.$data{'cover_minute'}.':00Z';

    # auto slug?
    if (!$data{"slug"}) {
        $data{"slug"} = $briclite->make_slug($data{"name"});
    }

    # more data
    $data{"fname"} = $session->param("fname");
    $data{"mname"} = $session->param("mname");
    $data{"lname"} = $session->param("lname");
    $data{"type"} = "Writers";
    $data{"role"} = "DEFAULT";
    $data{"story_xml"} = MIME::Base64::decode($data{"story_xml"}) if ($data{"story_xml"});

    my $stat;
    if ($cgi->param('submit')) {
        $briclite->logmessage("save story ".$cgi->param('story_id')." requested by user ".$session->param('username'));
        $story_id = $briclite->save_story(\%data);
    } elsif ($cgi->param('publish')) {
        $briclite->logmessage("save and publish story ".$cgi->param('story_id')." requested by user ".$session->param('username'));
        $story_id = $briclite->save_and_publish_story(\%data);
    }

    if ($cgi->param('submit') || $cgi->param('publish')) {
        print "<p class=\"success\">Your post has been saved.</p>";
    } else {
        print "<p class=\"success\">Your post has been published.</p>";
    }
    print "<p><a href='home.cgi'>&laquo; back to list of recent posts</a></p>";
}

my ($uuid, $name, $slug, $enc_xml, @keywords, $selected_category, $ext_url);
my ($deck);

my $backurl = 'home.cgi';

# are we editing an existing story?
if ($story_id) {
    my $story_xml = $briclite->get_story_xml($story_id);
    $enc_xml = MIME::Base64::encode($story_xml, "");

    my $parser = XML::LibXML->new;
    my $doc = $parser->parse_string($story_xml);
    my $root = $doc->getDocumentElement;

    # check permissions
    my $allowed = 0;
    foreach my $contributor ($root->getElementsByLocalName('contributor')) {
        if (@{$contributor->getElementsByLocalName('fname')}[0]->textContent eq $session->param('fname') && @{$contributor->getElementsByLocalName('lname')}[0]->textContent eq $session->param('lname')) {
            $allowed = 1;
        }
    }
    my $fullname = $session->param('fname')." ".$session->param('lname');
    if (@{$root->getElementsByLocalName('description')}[0]->textContent =~ m/$fullname/) {
        $allowed = 1;
    }

    if (!$allowed) {
        print "<p class=\"error\">You do not have access to edit this story.</p>";
        print "<p><a href='$backurl'>Back</a></p>";
        print $cgi->end_html;
        exit;
    }

#    print "<textarea rows='10' cols='80'>$story_xml</textarea><br/>";
    $uuid = @{$root->getElementsByLocalName('story')}[0]->getAttribute('uuid');
    $name = @{$root->getElementsByLocalName('name')}[0]->textContent;
    $slug = @{$root->getElementsByLocalName('slug')}[0]->textContent;

    if (@{$root->getElementsByLocalName('primary_uri')}[0]->textContent && @{$root->getElementsByLocalName('publish_status')}[0]->textContent) {
        $ext_url = "http://www.sportsnet.ca".@{$root->getElementsByLocalName('primary_uri')}[0]->textContent;
    }

    foreach my $cat ($root->getElementsByLocalName('category')) {
        $selected_category = $cat->textContent;
    }

    foreach my $key ($root->getElementsByLocalName('keyword')) {
        push @keywords, $key->textContent;
    }

    foreach my $field ($root->getElementsByLocalName('field')) {
        if ($field->getAttribute('type') eq 'deck') {
            $deck = $field->textContent;
        }
    }

    my $cover_date = @{$root->getElementsByLocalName('cover_date')}[0]->textContent;
    ($cover_year, $cover_month, $cover_day, $cover_hour, $cover_minute) = $cover_date =~ m/([0-9]+)-([0-9]+)-([0-9]+)T([0-9]+):([0-9]+)/;

} else {
    # not editing an existing story
    my $dt = DateTime->now;
    ($cover_year, $cover_month, $cover_day, $cover_hour, $cover_minute) = $dt->strftime('%FT%TZ') =~ m/([0-9]+)-([0-9]+)-([0-9]+)T([0-9]+):([0-9]+)/;
}


my $category_options;
{ # set up categories
    my $categories = $briclite->get_categories;
    my ($path, $name);
    foreach (keys %{$categories}) {
        $name = $categories->{$_};
        $category_options .= "<option value='$_'".($selected_category eq $_ ? " selected='selected'" : "").">$name</option>\n";
    }
}

# the actual form
print "<p><a href=\"$ext_url\" target=\"_blank\">See the published version of this post</a></p>" if ($ext_url);

print <<EOT;

<form method="post" onsubmit="return validate();">
<input type="hidden" name="story_id" value="$story_id" />
<input type="hidden" name="uuid" value="$uuid" />
<input type="hidden" name="story_xml" value="$enc_xml" />

<label for="name">
Post Title:
</label> 
<input type="text" name="name" id="name" value="$name" /><br/>

EOT

sub print_select
{
    my $id = shift;
    my $options = shift;
    my $selected = shift;

    print '<select id="'.$id.'" name="'.$id.'" style="width: auto;">';

    if (ref($options) eq 'ARRAY') {
        foreach (@$options) {
            $_ = substr("0$_", -2) if ($id eq 'cover_day' || $id eq 'cover_hour' || $id eq 'cover_minute');
            print "<option value='$_'".($_ eq $selected || $_ == $selected ? ' selected="selected"' : '').">$_</option>";
        }
    } elsif (ref($options) eq 'HASH') {
        foreach (sort keys %$options) {
            print "<option value='$_'".($_ eq $selected || $_ == $selected ? ' selected="selected"' : '').">".$options->{$_}."</option>";
        }
    }

    print "</select>\n";
}

my $dt = DateTime->now;
print "<label>Post date/time:</label>";

print_select('cover_month', {'01' => 'January', '02'=>'February', '03'=>'March', '04'=>'April', '05'=>'May', '06'=>'June', '07'=>'July', '08'=>'August', '09'=>'September', '10'=>'October', '11'=>'November', '12'=>'December'}, $cover_month);
print_select('cover_day', [1..31], $cover_day);
print_select('cover_year', [$dt->strftime('%Y')-1 .. $dt->strftime('%Y')+1], $cover_year);
print ", ";

print_select('cover_hour', [00..23], $cover_hour);
print ":";
print_select('cover_minute', [00..60], $cover_minute);

print <<EOT;
<!--
$cover_year
$cover_month
$cover_day
$cover_hour
$cover_minute
-->

<label for="slug">
Slug (optional):
</label> 
<input type="text" name="slug" id="slug" value="$slug" /><br/>

<label for="categories">
Category: 
</label>
<select name="categories" id="categories" />
$category_options
</select>

<label for="deck">
Deck:
</label>
<textarea rows="8" cols="76" name="deck" id="deck">
$deck
</textarea>

<br/><br/>

<input type="submit" class="wymupdate" name="submit" value="Save and Continue" />
<input type="submit" class="wymupdate" name="publish" value="Save and Publish" />
<input type="button" class="cancel" name="back" value="Cancel without saving" onclick="if (confirm('Are you sure you want to go back without saving?')) { window.location.href='$backurl'; }" />
</form>

<br/>

<div id="errors" style="color: red;">
</div>
</div>

<div id="saveDialog" style="text-align: center; display: none; background: white;">
<p><strong>Your post is being processed.</strong></p>
<p>Please be patient as this can take a few minutes.</p>
<p><img src="images/spin.gif" alt="spin" /></p>
</div>

<script type="text/javascript">

jQuery(function() {
        jQuery('#deck').wymeditor({
            preInit: function(wym) {
                wym._options.iframeHtml = wym._options.iframeHtml.replace(/<iframe/, '<iframe style="height: 200px;"'); 
            }, 
            classesHtml: '',
            boxHtml:   "<div class='wym_box'>"
              + "<div class='wym_area_top'>"
              + WYMeditor.TOOLS
              + WYMeditor.CONTAINERS
              + "</div>"
              + "<div class='wym_area_left'></div>"
              + "<div class='wym_area_right'>"
              + "</div>"
              + "<div class='wym_area_main'>"
              + WYMeditor.HTML
              + WYMeditor.IFRAME
              + WYMeditor.STATUS
              + "</div>"
              + "<div class='wym_area_bottom'>"
              + "</div>"
              + "</div>",

            postInit: function(wym) {
                jQuery(this._box).find(".wym_classes, .wym_containers")
                    .css("width", "160px")
                    .css("float", "left")
                    .css("margin-right", "5px")
                    .find("ul")
                    .css("width", "140px");
            }

            });
});


function validate()
{
    var errors = '';
    if (!jQuery("#name").get(0).value) {
        errors = errors + "Enter a title for this post.<br/>";
    }

    jQuery("#errors").get(0).innerHTML = errors;

    if (!errors) {
        jQuery("#saveDialog").get(0).style.display = '';
        jQuery("#saveDialog").dialog({ 
            modal: true, 
            draggable: false,
            resizable: false,
            height: 160,
            width: 360,
            title: 'Please wait',
            overlay: { 
                opacity: 0.5, 
                background: "black" 
            } 
        });
    }

    return (!errors);
}

</script>

EOT

print $cgi->end_html;

