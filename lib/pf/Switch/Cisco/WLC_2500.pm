package pf::Switch::Cisco::WLC_2500;

=head1 NAME

pf::Switch::Cisco::WLC_2500 - Object oriented module to parse SNMP traps and 
manage Cisco Wireless Controllers 2500 Series

=head1 STATUS

This module is currently only a placeholder, see L<pf::Switch::Cisco::WLC> for relevant support items.

=cut

use strict;
use warnings;

use Log::Log4perl;
use Net::SNMP;

use base ('pf::Switch::Cisco::WLC');

sub description { 'Cisco Wireless (WLC) 2500 Series' }

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
