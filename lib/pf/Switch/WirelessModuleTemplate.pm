package pf::Switch::WirelessModuleTemplate;

=head1 NAME

pf::Switch::WirelessModuleTemplate

=head1 SYNOPSIS

The pf::Switch::WirelessModuleTemplate module implements an object oriented interface to 
manage <HARDWARE>

=head1 STATUS

Developed and tested on <model> running <firmware>

=over

=item Supports

=over

=item <feature a>

=item <feature b>

=back

=back

=head1 BUGS AND LIMITATIONS

=over

=item <problem a>

<problem description>

=back

=cut

use strict;
use warnings;

use base ('pf::Switch');
use Log::Log4perl;

use pf::config;

=head1 SUBROUTINES

=over

=cut

# CAPABILITIES
# access technology supported
sub supportsWirelessDot1x { return $TRUE; }
sub supportsWirelessMacAuth { return $TRUE; }
# inline capabilities
sub inlineCapabilities { return ($MAC,$SSID); }

=item getVersion

obtain image version information from switch

=cut

sub getVersion {
    # IMPLEMENT!
}

=item parseTrap

=cut

sub parseTrap {
    # Optional for Wireless devices
    my ( $this, $trapString ) = @_;
    my $trapHashRef;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    
    $logger->debug("trap currently not handled");
    $trapHashRef->{'trapType'} = 'unknown';
        
    return $trapHashRef;
}

=item deauthenticateMacDefault

deauthenticate a MAC address from wireless network (including 802.1x)

=cut

sub deauthenticateMacDefault {
    # IMPLEMENT!
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

# vim: set shiftwidth=4:
# vim: set expandtab:
# vim: set backspace=indent,eol,start:
