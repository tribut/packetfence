package pf::Switch::HP;

=head1 NAME

pf::Switch::HP- Object oriented module to access SNMP enabled HP switches

=head1 SYNOPSIS

The pf::Switch::HP module implements an object oriented interface
to access SNMP enabled HP switches.

=head1 BUGS AND LIMITATIONS

=over

=item Port Security notice

Note: HP ProCurve only sends one security trap to PacketFence per security violation so make sure PacketFence runs when you configure port-security. Also, because of the above limitation, it is considered good practice to reset the intrusion flag as a first troubleshooting step.

If you want to learn more about intrusion flag and port-security, please refer to the ProCurve documentation.

Warning: If you configure a switch that is already in production be careful that enabling port-security causes active MAC addresses to be automatically added to the intrusion list without a security trap sent to PacketFence. This is undesired because PacketFence will not be notified that it needs to configure the port. As a work-around, unplug clients before activating port-security or remove the intrusion flag after you enabled port-security with: port-security <port> clear-intrusion-flag.

=back

=cut

use strict;
use warnings;

use base ('pf::Switch');
use Log::Log4perl;
use Net::SNMP;

use pf::Switch::constants;
use pf::util;

=head1 METHODS

TODO: This list is incomplete

=over

=cut

sub getVersion {
    my ($this)                = @_;
    my $oid_hpSwitchOsVersion = '1.3.6.1.4.1.11.2.14.11.5.1.1.3.0';
    my $logger                = Log::Log4perl::get_logger( ref($this) );
    if ( !$this->connectRead() ) {
        return '';
    }
    $logger->trace(
        "SNMP get_request for hpSwitchOsVersion: $oid_hpSwitchOsVersion");
    my $result = $this->{_sessionRead}
        ->get_request( -varbindlist => [$oid_hpSwitchOsVersion] );
    if ( exists( $result->{$oid_hpSwitchOsVersion} )
        && ( $result->{$oid_hpSwitchOsVersion} ne 'noSuchInstance' ) )
    {
        return $result->{$oid_hpSwitchOsVersion};
    }
    return '';
}

sub parseTrap {
    my ( $this, $trapString ) = @_;
    my $trapHashRef;
    my $logger = Log::Log4perl::get_logger( ref($this) );

    #-- secureMacAddrViolation SNMP v1 & v2c
    if ( $trapString
        =~ /BEGIN VARIABLEBINDINGS \.1\.3\.6\.1\.4\.1\.11\.2\.14\.2\.10\.2\.1\.2\.1\.\d+ = INTEGER: 1\|\.1\.3\.6\.1\.4\.1\.11\.2\.14\.2\.10\.2\.1\.3\.1\.(\d+) = INTEGER: \d+\|\.1\.3\.6\.1\.4\.1\.11\.2\.14\.2\.10\.2\.1\.4\.1\.\d+ = $SNMP::MAC_ADDRESS_FORMAT/ ) {

        $trapHashRef->{'trapType'} = 'secureMacAddrViolation';
        $trapHashRef->{'trapIfIndex'} = $1;
        $trapHashRef->{'trapMac'} = parse_mac_from_trap($2);
        $trapHashRef->{'trapVlan'} = $this->getVlan( $trapHashRef->{'trapIfIndex'} );

    #-- secureMacAddrViolation SNMP v3
    } elsif ( $trapString
        =~ /BEGIN VARIABLEBINDINGS.*OID: \.1\.3\.6\.1\.4\.1\.11\.2\.14\.12\.4\.0\.\d+\|\.1\.3\.6\.1\.4\.1\.11\.2\.14\.2\.10\.2\.1\.2\.1\.\d+ = INTEGER: 1\|\.1\.3\.6\.1\.4\.1\.11\.2\.14\.2\.10\.2\.1\.3\.1\.(\d+) = INTEGER: \d+\|\.1\.3\.6\.1\.4\.1\.11\.2\.14\.2\.10\.2\.1\.4\.1\.\d+ = $SNMP::MAC_ADDRESS_FORMAT/ ) {   

        $trapHashRef->{'trapType'} = 'secureMacAddrViolation';
        $trapHashRef->{'trapIfIndex'} = $1;
        $trapHashRef->{'trapMac'} = parse_mac_from_trap($2);
        $trapHashRef->{'trapVlan'} = $this->getVlan( $trapHashRef->{'trapIfIndex'} );

    #link up/down
    } elsif ( $trapString
        =~ /BEGIN TYPE ([23]) END TYPE BEGIN SUBTYPE 0 END SUBTYPE BEGIN VARIABLEBINDINGS \.1\.3\.6\.1\.2\.1\.2\.2\.1\.1\.([0-9]+) = INTEGER: [0-9]+ END VARIABLEBINDINGS/
        )
    {
        $trapHashRef->{'trapType'} = ( ( $1 == 2 ) ? "down" : "up" );
        $trapHashRef->{'trapIfIndex'} = $2;
    } else {
        $logger->debug("trap currently not handled");
        $trapHashRef->{'trapType'} = 'unknown';
    }
    return $trapHashRef;
}

sub _setVlan {
    my ( $this, $ifIndex, $newVlan, $oldVlan, $switch_locker_ref ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    if ( !$this->connectRead() ) {
        return 0;
    }
    my $OID_dot1qPvid = '1.3.6.1.2.1.17.7.1.4.5.1.1';    # Q-BRIDGE-MIB
    my $OID_dot1qVlanStaticUntaggedPorts
        = '1.3.6.1.2.1.17.7.1.4.3.1.4';                  # Q-BRIDGE-MIB
    my $OID_dot1qVlanStaticEgressPorts
        = '1.3.6.1.2.1.17.7.1.4.3.1.2';                  # Q-BRIDGE-MIB
    my $result;

    $logger->trace( "locking - trying to lock \$switch_locker{"
            . $this->{_id}
            . "} in _setVlan" );
    {
        lock %{ $switch_locker_ref->{ $this->{_id} } };
        $logger->trace( "locking - \$switch_locker{"
                . $this->{_id}
                . "} locked in _setVlan" );

        # get current egress and untagged ports
        $this->{_sessionRead}->translate(0);
        $logger->trace(
            "SNMP get_request for dot1qVlanStaticUntaggedPorts and dot1qVlanStaticEgressPorts"
        );
        $result = $this->{_sessionRead}->get_request(
            -varbindlist => [
                "$OID_dot1qVlanStaticEgressPorts.$oldVlan",
                "$OID_dot1qVlanStaticEgressPorts.$newVlan",
                "$OID_dot1qVlanStaticUntaggedPorts.$oldVlan",
                "$OID_dot1qVlanStaticUntaggedPorts.$newVlan"
            ]
        );

        # calculate new settings
        my $egressPortsOldVlan
            = $this->modifyBitmask(
            $result->{"$OID_dot1qVlanStaticEgressPorts.$oldVlan"},
            $ifIndex - 1, 0 );
        my $egressPortsVlan
            = $this->modifyBitmask(
            $result->{"$OID_dot1qVlanStaticEgressPorts.$newVlan"},
            $ifIndex - 1, 1 );
        my $untaggedPortsOldVlan
            = $this->modifyBitmask(
            $result->{"$OID_dot1qVlanStaticUntaggedPorts.$oldVlan"},
            $ifIndex - 1, 0 );
        my $untaggedPortsVlan
            = $this->modifyBitmask(
            $result->{"$OID_dot1qVlanStaticUntaggedPorts.$newVlan"},
            $ifIndex - 1, 1 );
        $this->{_sessionRead}->translate(1);

        # set all values
        if ( !$this->connectWrite() ) {
            return 0;
        }

        $logger->trace(
            "SNMP set_request for egressPorts and untaggedPorts for old and new VLAN "
        );
        $result = $this->{_sessionWrite}->set_request(
            -varbindlist => [
                "$OID_dot1qVlanStaticEgressPorts.$newVlan",
                Net::SNMP::OCTET_STRING,
                $egressPortsVlan,
                "$OID_dot1qVlanStaticUntaggedPorts.$newVlan",
                Net::SNMP::OCTET_STRING,
                $untaggedPortsVlan,
                "$OID_dot1qVlanStaticUntaggedPorts.$oldVlan",
                Net::SNMP::OCTET_STRING,
                $untaggedPortsOldVlan,
                "$OID_dot1qVlanStaticEgressPorts.$oldVlan",
                Net::SNMP::OCTET_STRING,
                $egressPortsOldVlan
            ]
        );
        if ( !defined($result) ) {
            print $this->{_sessionWrite}->error . "\n";
            $logger->error(
                "error setting egressPorts and untaggedPorts for old and new vlan: "
                    . $this->{_sessionWrite}->error );
        }
    }
    $logger->trace( "locking - \$switch_locker{"
            . $this->{_id}
            . "} unlocked in _setVlan" );
    return ( defined($result) );
}

sub getAllSecureMacAddresses {
    my ($this) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    my $OID_hpSecCfgStatus
        = '1.3.6.1.4.1.11.2.14.2.10.4.1.4';    #HP-ICF-GENERIC-RPTR
    my $hpSecCfgAddrGroupIndex = 1;

    my $secureMacAddrHashRef = {};
    if ( !$this->connectRead() ) {
        return $secureMacAddrHashRef;
    }

    $logger->trace(
        "SNMP get_table for hpSecCfgStatus: $OID_hpSecCfgStatus.$hpSecCfgAddrGroupIndex"
    );
    my $result = $this->{_sessionRead}->get_table(
        -baseoid => "$OID_hpSecCfgStatus.$hpSecCfgAddrGroupIndex" );
    while ( my ( $oid_including_mac, $status ) = each( %{$result} ) ) {
        if ((   $oid_including_mac
                =~ /^$OID_hpSecCfgStatus\.$hpSecCfgAddrGroupIndex\.([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/
            )
            && ( $status == 1 )
            )
        {
            my $ifIndex = $1;
            my $mac     = sprintf( "%02x:%02x:%02x:%02x:%02x:%02x",
                $2, $3, $4, $5, $6, $7 );
            push @{ $secureMacAddrHashRef->{$mac}->{$ifIndex} },
                $this->getVlan($ifIndex);
        }
    }

    return $secureMacAddrHashRef;
}

sub getSecureMacAddresses {
    my ( $this, $ifIndex ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    my $OID_hpSecCfgStatus
        = '1.3.6.1.4.1.11.2.14.2.10.4.1.4';    #HP-ICF-GENERIC-RPTR
    my $hpSecCfgAddrGroupIndex = 1;

    my $secureMacAddrHashRef = {};
    if ( !$this->connectRead() ) {
        return $secureMacAddrHashRef;
    }

    my $vlan = $this->getVlan($ifIndex);

    $logger->trace(
        "SNMP get_table for hpSecCfgStatus: $OID_hpSecCfgStatus.$hpSecCfgAddrGroupIndex.$ifIndex"
    );
    my $result = $this->{_sessionRead}->get_table(
        -baseoid => "$OID_hpSecCfgStatus.$hpSecCfgAddrGroupIndex.$ifIndex" );
    while ( my ( $oid_including_mac, $status ) = each( %{$result} ) ) {
        if ((   $oid_including_mac
                =~ /^$OID_hpSecCfgStatus\.$hpSecCfgAddrGroupIndex\.$ifIndex\.([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/
            )
            && ( $status == 1 )
            )
        {
            my $mac = sprintf( "%02x:%02x:%02x:%02x:%02x:%02x",
                $1, $2, $3, $4, $5, $6 );
            push @{ $secureMacAddrHashRef->{$mac} }, $vlan;
        }
    }

    return $secureMacAddrHashRef;
}

sub getMaxMacAddresses {
    my ( $this, $ifIndex ) = @_;
    my $logger                  = Log::Log4perl::get_logger( ref($this) );
    my $OID_hpSecPtAddressLimit = '1.3.6.1.4.1.11.2.14.2.10.3.1.3';
    my $OID_hpSecPtLearnMode    = '1.3.6.1.4.1.11.2.14.2.10.3.1.4';
    my $hpSecCfgAddrGroupIndex  = 1;

    if ( !$this->connectRead() ) {
        return -1;
    }

    #determine if port security is enabled
    $logger->trace(
        "SNMP get_request for hpSecPtLearnMode: $OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex"
    );
    my $result = $this->{_sessionRead}->get_request( -varbindlist =>
            [ "$OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex" ] );
    if ((   !exists(
                $result->{
                    "$OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex"}
            )
        )
        || ($result->{
                "$OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex"} eq
            'noSuchInstance' )
        )
    {
        $logger->error("ERROR: could not obtain hpSecPtLearnMode");
        return -1;
    }
    if ( $result->{"$OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex"}
        != 4 )
    {
        $logger->debug("hpSecPtLearnMode is not configureSpecific(4)");
        return -1;
    }

    #determine max number of MAC addresses allowed
    $logger->trace(
        "SNMP get_request for hpSecPtAddressLimit: $OID_hpSecPtAddressLimit.$hpSecCfgAddrGroupIndex.$ifIndex"
    );
    $result = $this->{_sessionRead}->get_request( -varbindlist =>
            [ "$OID_hpSecPtAddressLimit.$hpSecCfgAddrGroupIndex.$ifIndex" ] );
    if ((   !exists(
                $result->{
                    "$OID_hpSecPtAddressLimit.$hpSecCfgAddrGroupIndex.$ifIndex"
                    }
            )
        )
        || ($result->{
                "$OID_hpSecPtAddressLimit.$hpSecCfgAddrGroupIndex.$ifIndex"}
            eq 'noSuchInstance' )
        )
    {
        print "and down here\n";
        $logger->error("ERROR: could not obtain hpSecPtAddressLimit");
        return -1;
    }
    return $result->{
        "$OID_hpSecPtAddressLimit.$hpSecCfgAddrGroupIndex.$ifIndex"};
}

sub authorizeMAC {
    my ( $this, $ifIndex, $deauthMac, $authMac, $deauthVlan, $authVlan ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );

    if ( ($deauthMac) && ( !$this->isFakeMac($deauthMac) ) ) {
        $this->_authorizeMAC( $ifIndex, $deauthMac, 0 );
    }
    if ( ($authMac) && ( !$this->isFakeMac($authMac) ) ) {
        $this->_authorizeMAC( $ifIndex, $authMac, 1 );
    }
    return 1;
}

#called with $authorized set to true, creates a new line to authorize the MAC
#called with $authorized set to false, deletes an existing line
# In both case, resets IntrusionFlag
sub _authorizeMAC {
    my ( $this, $ifIndex, $MACHexString, $authorize ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );
    my $OID_hpSecCfgStatus
        = '1.3.6.1.4.1.11.2.14.2.10.4.1.4';    #HP-ICF-GENERIC-RPTR
    my $OID_hpSecPtIntrusionFlag
        = '1.3.6.1.4.1.11.2.14.2.10.3.1.7';    #HP-ICF-GENERIC-RPTR
    my $hpSecCfgAddrGroupIndex = 1;

    if ( !$this->isProductionMode() ) {
        $logger->info(
            "not in production mode ... we won't add or delete an entry from the hpSecureCfgAddrTable"
        );
        return 1;
    }

    #convert MAC into decimal
    my @MACArray = split( /:/, $MACHexString );
    my $MACDecString = '';
    foreach my $hexPiece (@MACArray) {
        if ( $MACDecString ne '' ) {
            $MACDecString .= ".";
        }
        $MACDecString .= hex($hexPiece);
    }

    if ( !$this->connectWrite() ) {
        return 0;
    }

    $logger->trace(
        "SNMP set_request for hpSecCfgStatus: $OID_hpSecCfgStatus.$hpSecCfgAddrGroupIndex.$ifIndex.$MACDecString"
    );
    my $result = $this->{_sessionWrite}->set_request(
        -varbindlist => [
            "$OID_hpSecCfgStatus.$hpSecCfgAddrGroupIndex.$ifIndex.$MACDecString",
            Net::SNMP::INTEGER,
            ($authorize) ? 4 : 6,
            "$OID_hpSecPtIntrusionFlag.$hpSecCfgAddrGroupIndex.$ifIndex",
            Net::SNMP::INTEGER,
            2,
        ]
    );
    return ( defined($result) );
}

sub isDynamicPortSecurityEnabled {
    my ( $this, $ifIndex ) = @_;
    return 0;
}

sub isStaticPortSecurityEnabled {
    my ( $this, $ifIndex ) = @_;
    return $this->isPortSecurityEnabled($ifIndex);
}

sub setPortSecurityEnableByIfIndex {
    my ( $this, $ifIndex, $trueFalse ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );

    $logger->info("function not implemented yet");
    return 1;
}

sub isPortSecurityEnabled {
    my ( $this, $ifIndex ) = @_;
    my $logger = Log::Log4perl::get_logger( ref($this) );

    my $OID_hpSecPtLearnMode   = '1.3.6.1.4.1.11.2.14.2.10.3.1.4';
    my $OID_hpSecPtAlarmEnable = '1.3.6.1.4.1.11.2.14.2.10.3.1.6';
    my $hpSecCfgAddrGroupIndex = 1;

    if ( !$this->connectRead() ) {
        return 0;
    }

    $logger->trace(
        "SNMP get_next_request for hpSecPtLearnMode: $OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex and hpSecPtAlarmEnable: $OID_hpSecPtAlarmEnable.$hpSecCfgAddrGroupIndex.$ifIndex"
    );
    my $result = $this->{_sessionRead}->get_request(
        -varbindlist => [
            "$OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex",
            "$OID_hpSecPtAlarmEnable.$hpSecCfgAddrGroupIndex.$ifIndex"
        ]
    );
    return (
        defined(
            $result->{
                "$OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex"}
            )
            && defined(
            $result->{
                "$OID_hpSecPtAlarmEnable.$hpSecCfgAddrGroupIndex.$ifIndex"}
            )
            && (
            $result->{
                "$OID_hpSecPtLearnMode.$hpSecCfgAddrGroupIndex.$ifIndex"}
            == 4 )
            && (
            $result->{
                "$OID_hpSecPtAlarmEnable.$hpSecCfgAddrGroupIndex.$ifIndex"}
            == 2 )
    );
}

sub getVlanFdbId {
    my ( $this, $vlan ) = @_;
    my $OID_dot1qVlanFdbId = '1.3.6.1.2.1.17.7.1.4.2.1.3.0';    #Q-BRIDGE-MIB
    my $logger = Log::Log4perl::get_logger( ref($this) );

    if ( !$this->connectRead() ) {
        return 0;
    }

    $logger->trace(
        "SNMP get_request for dot1qVlanFdbId $OID_dot1qVlanFdbId.$vlan");
    my $result = $this->{_sessionRead}
        ->get_request( -varbindlist => ["$OID_dot1qVlanFdbId.$vlan"] );

    if ( !defined($result) ) {
        return 0;
    } else {
        return $result->{"$OID_dot1qVlanFdbId.$vlan"};
    }
}

=item isVoIPEnabled

Supports VoIP if enabled.

=cut

sub isVoIPEnabled {
    my ($self) = @_;
    return ( $self->{_VoIPEnabled} == 1 );
}

=item getVoiceVlan

In what VLAN should a VoIP device be.

=cut

sub getVoiceVlan {
    my ($this, $ifIndex) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));

    my $voiceVlan = $this->getVlanByName('voice');
    if (defined($voiceVlan)) {
        return $voiceVlan;
    }

    # otherwise say it didn't work
    $logger->warn("Voice VLAN was requested but it's not configured!");
    return -1;
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
