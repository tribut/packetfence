package pf::web::dispatcher;
=head1 NAME

dispatcher.pm

=cut

use strict;
use warnings;

use Apache2::Const -compile => qw(OK DECLINED HTTP_MOVED_TEMPORARILY);
use Apache2::Request;
use Apache2::RequestIO ();
use Apache2::RequestRec ();
use Apache2::Response ();
use Apache2::RequestUtil ();
use Apache2::ServerRec;

use APR::Table;
use APR::URI;
use Log::Log4perl;
use Template;
use URI::Escape qw(uri_escape);

use pf::config;
use pf::util;
use pf::web::constants;
use pf::proxypassthrough::constants;
use pf::Portal::Session;
use pf::iplog qw(iplog_update);

=head1 SUBROUTINES

=over

=item translate

Implementation of PerlTransHandler. Rewrite all URLs except those explicitly
allowed by the Captive portal.

For simplicity and performance this doesn't consume and leverage 
L<pf::Portal::Session>.

Reference: http://perl.apache.org/docs/2.0/user/handlers/http.html#PerlTransHandler

=cut

sub handler {
    my $r = Apache::SSLLookup->new(shift);
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->trace("hitting translator with URL: " . $r->uri);

    # Test if the hostname is include in the proxy_passthroughs configuration
    # In this case forward to mad_proxy
    if ( ( $r->hostname =~ /$PROXYPASSTHROUGH::ALLOWED_PASSTHROUGH_DOMAINS/o && $PROXYPASSTHROUGH::ALLOWED_PASSTHROUGH_DOMAINS ne '') || ($r->hostname =~ /$PROXYPASSTHROUGH::ALLOWED_PASSTHROUGH_REMEDIATION_DOMAINS/o && $PROXYPASSTHROUGH::ALLOWED_PASSTHROUGH_REMEDIATION_DOMAINS ne '') ) {
        my $parsed_request = APR::URI->parse($r->pool, $r->uri);
        $parsed_request->hostname($r->hostname);
        $parsed_request->scheme('http');
        $parsed_request->scheme('https') if $r->is_https;
        $parsed_request->path($r->uri);
        return proxy_redirect($r, $parsed_request->unparse);
    }

    # be careful w/ performance here
    # Warning: we might want to revisit the /o (compile Once) if we ever want
    #          to reload Apache dynamically. pf::web::constants will need some
    #          rework also
    if ($r->uri =~ /$WEB::ALLOWED_RESOURCES/o) {
        my $s = $r->server();
        my $proto = isenabled($Config{'captive_portal'}{'secure_redirect'}) ? $HTTPS : $HTTP;
        #Because of chrome captiv portal detection we have to test if the request come from http request
        my $parsed = APR::URI->parse($r->pool,$r->headers_in->{'Referer'});
        if ($s->port eq '80' && $proto eq 'https' && $r->uri !~ /$WEB::ALLOWED_RESOURCES/o && $parsed->path !~ /$WEB::ALLOWED_RESOURCES/o) {
            #Generate a page with a refresh tag
            $r->handler('modperl');
            $r->set_handlers( PerlResponseHandler => \&html_redirect );
            return Apache2::Const::OK;
        } else {
            # DECLINED tells Apache to continue further mod_rewrite / alias processing
            return Apache2::Const::DECLINED;
        }
    }
    if ($r->uri =~ /$WEB::ALLOWED_RESOURCES_MOD_PERL/o) {
        $r->handler('modperl');
        $r->pnotes->{session_id} = $1;
        $r->set_handlers( PerlResponseHandler => ['pf::web::wispr'] );
        return Apache2::Const::OK;
    }

    # fallback to a redirection: inject local redirection handler
    $r->handler('modperl');
    $r->set_handlers( PerlResponseHandler => \&redirect );
    # OK tells Apache to stop further mod_rewrite / alias processing
    return Apache2::Const::OK;
}

=item external_captive_portal

Instantiate the switch module and use a specific captive portal

=cut

sub external_captive_portal {
    my ($switchId, $req,$r) = @_;
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    my $switch;
    if (valid_ip($switchId)) {
        $switch = pf::SwitchFactory->getInstance()->instantiate({switch_ip => $switchId});
    } elsif (valid_mac($switchId)) {
        $switch = pf::SwitchFactory->getInstance()->instantiate({switch_mac => $switchId});
    }
    if (defined($switch) && $switch->supportsExternalPortal) {
        my $portalSession = pf::Portal::Session->new();
        my ($client_mac,$client_ssid,$client_ip,$redirect_url,$grant_url,$status_code) = $switch->parseUrl(\$req);
        $portalSession->setClientIp($client_ip) if (defined($client_ip));
        $portalSession->setClientMac($client_mac) if (defined($client_mac));
        $portalSession->setDestinationUrl($redirect_url) if (defined($redirect_url));
        $portalSession->setGrantUrl($grant_url) if (defined($grant_url));
        $portalSession->cgi->param("do_not_deauth", $TRUE) if (defined($grant_url));
        iplog_update($client_mac,$client_ip,100) if (defined ($client_ip) && defined ($client_mac));
        # Have to update location_log ...
        return $portalSession->session->id();
    } else {
        return 0;
    }
} 
=item handler

For simplicity and performance this doesn't consume and leverage 
L<pf::Portal::Session>.

=cut

sub redirect {
    my ($r) = @_;
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->trace('hitting redirector');

    # External Captive Portal Detection

    my $req = Apache2::Request->new($r);
    foreach my $param ($req->param) {
        if ($param =~ /$WEB::EXTERNAL_PORTAL_PARAM/o) {
            my $cgi_session_id = external_captive_portal($req->param($param),$req,$r);
            if ($cgi_session_id ne '0') {
                # Set the cookie for the captive portal
                $r->err_headers_out->add('Set-Cookie' => "CGISESSID=".  $cgi_session_id . "; path=/");
            }
            last;
        }
    }

    my $proto;
    # Google chrome hack redirect in http
    if ($r->uri =~ /\/generate_204/) {
        $proto = $HTTP;
    } else {
        $proto = isenabled($Config{'captive_portal'}{'secure_redirect'}) ? $HTTPS : $HTTP;
    }

    my $stash = {
        'login_url' => "$proto://".$Config{'general'}{'hostname'}.".".$Config{'general'}{'domain'}."/captive-portal",
        'login_url_wispr' => "$proto://".$Config{'general'}{'hostname'}.".".$Config{'general'}{'domain'}."/wispr",
    };

    # prepare custom REDIRECT response
    my $response;
    my $template = Template->new({
        INCLUDE_PATH => [$CAPTIVE_PORTAL{'TEMPLATE_DIR'}],
    });
    $template->process( "redirection.tt", $stash, \$response ) || $logger->error($template->error());;

    # send out the redirection in a custom response
    # a custom response is required otherwise Apache take over the rendering
    # of redirects and we are unable to inject the WISPR XML
    $r->headers_out->set('Location' => $stash->{'login_url'});
    $r->content_type('text/html');
    $r->no_cache(1);
    $r->custom_response(Apache2::Const::HTTP_MOVED_TEMPORARILY, $response);
    return Apache2::Const::HTTP_MOVED_TEMPORARILY;
}

=item html_redirect

html redirection to captive portal

=cut

sub html_redirect {
    my ($r) = @_;
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->trace('hitting html redirector');

    my $proto = isenabled($Config{'captive_portal'}{'secure_redirect'}) ? $HTTPS : $HTTP;
    my $stash = {
        'login_url' => "$proto://".$Config{'general'}{'hostname'}.".".$Config{'general'}{'domain'}."/captive-portal",
    };

    # prepare custom REDIRECT response
    my $response;
    my $template = Template->new({
        INCLUDE_PATH => [$CAPTIVE_PORTAL{'TEMPLATE_DIR'}],
    });
    $template->process( "redirection.html", $stash, \$response ) || $logger->error($template->error());;
    $r->content_type('text/html');
    $r->no_cache(1);
    $r->print($response);
    return Apache2::Const::OK;
}

=item proxy_redirect

Mod_proxy redirect

=cut

sub proxy_redirect {
        my ($r, $url) = @_;
        my $logger = Log::Log4perl->get_logger(__PACKAGE__);
        $r->set_handlers(PerlResponseHandler => []);
        $r->filename("proxy:".$url);
        $r->proxyreq(2);
        $r->handler('proxy-server');
        return Apache2::Const::OK;
}

=back

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2013 Inverse inc.

=head1 LICENSE
    
This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.
    
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
            
You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.            
                
=cut

1;

