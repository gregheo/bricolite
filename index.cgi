#!/usr/bin/perl

use strict;

use CGI;
use CGI::Cookie;
use CGI::Session ('-ip_match');

my $cgi = new CGI;
my $session = new CGI::Session(undef, $cgi, {Directory=>'/tmp'});

if ($session->param('username')) {
    my $cookie = new CGI::Cookie(-name=>'CGISESSID', -value=>$session->id);
    print $cgi->header(-cookie=>$cookie, -location => 'home.cgi');
    exit;
}

print $session->header;
print $cgi->start_html(-title => 'Welcome to bricolite!',
					   -class=>'login',
                       -style => { -src => 'briclite.css' },
                       -script => [ {-language => 'JavaScript', -src=>'jquery/jquery.js'}
                                    ]);
print '<div id="content">';
print '<form method="post" action="login.cgi">';
print "<fieldset><legend>Please log in</legend>";

print "<p style='color: red;'>Invalid username or password.</p>" if $cgi->param('error');
my $username = $cgi->param('username') || "";

print <<EOT;

<label for="username" accesskey="u">
Username:
</label>

<input type="text" name="username" id="username" value="$username" size="30" />

<label for="password" accesskey="p">
Password:
</label>

<input type="password" id="password" name="password" size="30" />

<p>
<input type="submit" name="login" id="login" value="Log In" onclick="return validate();" />
</p>
</fieldset>
</form>

<div id="errors" style="color: red;">
</div>

<script type="text/javascript">
function validate()
{
    var errors = '';
    if (!jQuery("#username").get(0).value) {
        errors = errors + "Please enter your username.<br/>";
    }

    jQuery("#errors").get(0).innerHTML = errors;

    if (!errors) {
        login = jQuery("#login").get(0);
        login.value = 'Please wait...';
        return true;
    } else {
        return false;
    }
}

</script>
</div>

EOT

print $cgi->end_html;

