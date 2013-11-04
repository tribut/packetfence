package pf::Switch::Cisco::Aironet;

=head1 NAME

pf::Switch::Cisco::Aironet - Object oriented module to access SNMP enabled Cisco Aironet access points

=head1 SYNOPSIS

The pf::Switch::Cisco::Aironet module implements an object oriented interface
to access SNMP enabled Aironet access points.

=cut

=head1 BUGS AND LIMITATIONS

=over

=item VLAN sharing between SSIDs

The same VLAN cannot be shared between two SSIDs

=item SSID Identification

The Vendor Specific Attributes (VSA) needs to be enabled for SSID identification to work.

  radius-server vsa send authentication

=item CLI (telnet or ssh) deassociation

Wireless deauthentication (deassociation) uses the CLI (telnet or ssh) which is expensive (doesn't scale very well).

=item PSK and MAC-Authentication

Using Pre-Shared Key and MAC filtering (RADIUS MAC Authentication) is not possible on these devices.

=item flexconnect (H-REAP) limitations

Access Points in Hybrid Remote Edge Access Point (H-REAP) mode, now known as 
flexconnect, don't support RADIUS dynamic VLAN assignments (AAA override).

Customer specific work-arounds are possible. For example: per-SSID registration, auto-registration, etc.

=back

=cut

use strict;
use warnings;

use Carp;
use Log::Log4perl;
use Net::Appliance::Session;
use Net::SNMP;

use base ('pf::Switch::Cisco');

use pf::config;
use pf::util qw(format_mac_as_cisco);

=head1 SUBROUTINES

TODO: This list is incomplete

=over

=cut

# CAPABILITIES
# access technology supported
sub supportsWirelessDot1x { return $TRUE; }
sub supportsWirelessMacAuth { return $TRUE; }
# disabling special features supported by generic Cisco's but not on Aironet
sub supportsSaveConfig { return $FALSE; }
sub supportsCdp { return $FALSE; }
sub supportsLldp { return $FALSE; }
# inline capabilities
sub inlineCapabilities { return ($MAC,$SSID); }

=item deauthenticateMacDefault

Warning: this method should _never_ be called in a thread. Net::Appliance::Session is not thread 
safe: 

L<http://www.cpanforum.com/threads/6909/>

=cut

sub deauthenticateMacDefault {
    my ( $this, $mac ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );

    $mac = format_mac_as_cisco($mac);
    if ( !defined($mac) ) {
        $logger->error("ERROR: MAC format is incorrect. Aborting deauth...");
        # TODO return 1, really?
        return 1;
    }

    my $session;
    eval {
        $session = Net::Appliance::Session->new(
            Host      => $this->{_ip},
            Timeout   => 5,
            Transport => $this->{_cliTransport}
        );
        $session->connect(
            Name     => $this->{_cliUser},
            Password => $this->{_cliPwd}
        );
    };

    if ($@) {
        $logger->error(
            "ERROR: Can not connect to access point $this->{'_ip'} using "
                . $this->{_cliTransport} );
        return 1;
    }

    #if (! $session->enable($this->{_cliEnablePwd})) {
    #    $logger->error("ERROR: Can not 'enable' telnet connection");
    #    return 1;
    #}
    $logger->info("Deauthenticating mac $mac");
    $session->cmd("clear dot11 client $mac");
    $session->close();
    return 1;
}

sub isLearntTrapsEnabled {
    my ( $this, $ifIndex ) = @_;
    return ( 0 == 1 );
}

sub setLearntTrapsEnabled {
    my ( $this, $ifIndex, $trueFalse ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    $logger->error("function is NOT implemented");
    return -1;
}

sub isRemovedTrapsEnabled {
    my ( $this, $ifIndex ) = @_;
    return ( 0 == 1 );
}

sub setRemovedTrapsEnabled {
    my ( $this, $ifIndex, $trueFalse ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    $logger->error("function is NOT implemented");
    return -1;
}

sub getVmVlanType {
    my ( $this, $ifIndex ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    $logger->error("function is NOT implemented");
    return -1;
}

sub setVmVlanType {
    my ( $this, $ifIndex, $type ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    $logger->error("function is NOT implemented");
    return -1;
}

sub isTrunkPort {
    my ( $this, $ifIndex ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    $logger->error("function is NOT implemented");
    return -1;
}

sub getVlans {
    my ($this) = @_;
    my $vlans  = {};
    my $logger = Log::Log4perl::get_logger( ref($this) );
    $logger->error("function is NOT implemented");
    return $vlans;
}

sub isDefinedVlan {
    my ( $this, $vlan ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    $logger->error("function is NOT implemented");
    return 0;
}

sub isVoIPEnabled {
    my ($this) = @_;
    return 0;
}

=item extractSsid

Overriding default extractSsid because on Aironet AP SSID is in the Cisco-AVPair VSA.

=cut

# Same as in pf::Switch::Cisco::Aironet_WDS. Please keep both in sync. Once Moose push in a role.
sub extractSsid {
    my ($this, $radius_request) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));

    if (defined($radius_request->{'Cisco-AVPair'})) {

        if ($radius_request->{'Cisco-AVPair'} =~ /^ssid=(.*)$/) { # ex: Cisco-AVPair = "ssid=PacketFence-Secure"
            return $1;
        } else {
            $logger->info("Unable to extract SSID of Cisco-AVPair: ".$radius_request->{'Cisco-AVPair'});
        }
    }

    $logger->warn(
        "Unable to extract SSID for module " . ref($this) . ". SSID-based VLAN assignments won't work. "
        . "Make sure you enable Vendor Specific Attributes (VSA) on the AP if you want them to work."
    );
    return;
}

=item deauthTechniques

Return the reference to the deauth technique or the default deauth technique.

=cut

sub deauthTechniques {
    my ($this, $method) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    my $default = $SNMP::TELNET;
    my %tech = (
        $SNMP::TELNET => \&deauthenticateMacDefault,
    );

    if (!defined($method) || !defined($tech{$method})) {
        $method = $default;
    }
    return $method,$tech{$method};
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
