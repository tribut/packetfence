package pf::Switch::LG::ES4500G;

=head1 NAME

pf::Switch::LG::ES4500G - Object oriented module to access and configure enabled LG-Ericsson iPECS ES-4500G series.

=head1 STATUS

This module is currently only a placeholder, see pf::Switch::LG.

=cut

use strict;
use warnings;

use POSIX;
use Log::Log4perl;
use Net::SNMP;

use pf::Switch::constants;
use pf::config;
use pf::util;

use base ('pf::Switch::LG');

sub description { 'LG-Ericsson iPECS ES-4500G' }

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
