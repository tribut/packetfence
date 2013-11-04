package pf::Switch::Dlink::DES_3526;

=head1 NAME

pf::Switch::Dlink::DES_3526 - Object oriented module to access SNMP enabled Dlink DES 3526 switches

=head1 SYNOPSIS

The pf::Switch::Dlink::DES_3526 module implements an object oriented interface
to access SNMP enabled Dlink DES 3526 switches.

=cut

use strict;
use warnings;
use Log::Log4perl;
use Net::SNMP;
use base ('pf::Switch::Dlink');

sub description { 'D-Link DES 3526' }

=head1 AUTHOR

Treker Chen <treker.chen@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2008 Treker Chen

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
