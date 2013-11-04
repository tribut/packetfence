package pf::Switch::H3C;

=head1 NAME

pf::Switch::H3C - Object oriented module to access and configure enabled H3C switches.

=head1 STATUS

=over

=item Hardware

- Developed and tested on S5120-28C-PWR-EI using firmware 5.20 (2208P01)

=back

=cut

use strict;
use warnings;

use Log::Log4perl;
use Net::SNMP;
use POSIX;

use base ('pf::Switch');

use pf::config;
use pf::radius::constants;
use pf::Switch::constants;
use pf::util;


=head1 SUPPORTED TECHNOLOGIES

=over

=item supportsRadiusVoip

This switch module supports VoIP authorization over RADIUS.
Use getVoipVsa to return specific RADIUS attributes for VoIP to work.

=cut

sub supportsRadiusVoip { return $TRUE; }

=item supportsWiredDot1x

This switch module supports wired 802.1x authentication.

=cut

sub supportsWiredDot1x { return $TRUE; }

=item supportsWiredAuth

This switch module supports wired MAC authentication.

=cut

sub supportsWiredMacAuth { return $TRUE; }

# inline capabilities
sub inlineCapabilities { return ($MAC,$PORT); }

=back

=cut


=head1 SUBROUTINES

=over

=item getIfIndexForThisDot1dBasePort

Returns ifIndex for a given "normal" port number (dot1d)

Same as pf::Switch::ThreeCom::SS4500

=cut

#TODO consider subclassing ThreeCom to avoid code duplication
sub getIfIndexForThisDot1dBasePort {
    my ( $this, $dot1dBasePort ) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));
    # port number into ifIndex
    my $OID_dot1dBasePortIfIndex = '.1.3.6.1.2.1.17.1.4.1.2.'.$dot1dBasePort; # from BRIDGE-MIB

    if ( !$this->connectRead() ) {
        return 0;
    }

    $logger->trace( "SNMP get_request for dot1dBasePortIfIndex: $OID_dot1dBasePortIfIndex");
    my $result = $this->{_sessionRead}->get_request( -varbindlist => ["$OID_dot1dBasePortIfIndex"] );

    if (exists($result->{"$OID_dot1dBasePortIfIndex"})) {
        return $result->{"$OID_dot1dBasePortIfIndex"}; #return ifIndex (Integer)
    } else {
        return 0; #no ifIndex returned
    }
}

=item getVersion

Returns the software version of the slot.

=cut

sub getVersion {
    my ( $this ) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));

    my $OID_hh3cLswSysVersion = '1.3.6.1.4.1.25506.8.35.18.1.4';    # from HH3C-LSW-DEV-ADM-MIB
    my $slotNumber = '0';

    if ( !$this->connectRead() ) {
        return;
    }

    $logger->trace( "SNMP get_request for OID_hh3cLswSysVersion: ( $OID_hh3cLswSysVersion.$slotNumber )" );
    my $result = $this->{_sessionRead}->get_request( -varbindlist => [ "$OID_hh3cLswSysVersion.$slotNumber" ] );

    # Error handling
    if ( !defined($result) ) {
        $logger->warn("Asking for software version failed with " . $this->{_sessionRead}->error());
        return;
    }

    if ( !defined($result->{"$OID_hh3cLswSysVersion.$slotNumber"}) ) {
        $logger->error("Returned value doesn't exist!");
        return;
    }

    if ( $result->{"$OID_hh3cLswSysVersion.$slotNumber"} eq 'noSuchInstance' ) {
        $logger->warn("Asking for software version failed with noSuchInstance");
        return;
    }

    # Success
    return $result->{"$OID_hh3cLswSysVersion.$slotNumber"};
}

=item getVoipVsa {

Returns RADIUS attributes for voip phone devices.

=cut

sub getVoipVsa {
    my ( $this ) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));

    return (
        'Tunnel-Type'               => $RADIUS::VLAN,
        'Tunnel-Medium-Type'        => $RADIUS::ETHERNET,
        'Tunnel-Private-Group-ID'   => $this->getVlanByName('voice'),
    );
}

=item isVoIPEnabled

Supports VoIP if enabled.

=cut

sub isVoIPEnabled {
    my ($self) = @_;
    return ( $self->{_VoIPEnabled} == 1 );
}

=item NasPortToIfIndex

Same as pf::Switch::ThreeCom::Switch_4200G

=cut

#TODO consider subclassing ThreeCom to avoid code duplication
sub NasPortToIfIndex {
    my ($this, $nas_port) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));

    # 4096 NAS-Port slots are reserved per physical ports, 
    # I'm assuming that each client will get a +1 so I translate all of them into the same ifIndex
    # Also there's a large offset (16781312), couldn't find where it is coming from...
    my $port = ceil(($nas_port - $THREECOM::NAS_PORT_OFFSET) / $THREECOM::NAS_PORTS_PER_PORT_RANGE);
    if ($port > 0) {

        # TODO we should think about caching or pre-computation here
        my $ifIndex = $this->getIfIndexForThisDot1dBasePort($port);

        # return if defined and an int
        return $ifIndex if (defined($ifIndex) && $ifIndex =~ /^\d+$/);
    }

    # error reporting
    $logger->warn(
        "Unknown NAS-Port format. ifIndex translation could have failed. "
        . "VLAN re-assignment and switch/port accounting will be affected."
    );
    return $nas_port;
}

=item parseTrap

All traps ignored

=cut

sub parseTrap {
    my ( $this, $trapString ) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));

    my $trapHashRef;

    $logger->debug("trap ignored, since we're using 802.1x/mac-auth");
    $trapHashRef->{'trapType'} = 'unknown';

    return $trapHashRef;
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
