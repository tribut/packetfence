package pfappserver::Form::ConfigStore::Provisioning::mobileiron;

=head1 NAME

pfappserver::Form::ConfigStore::Provisioning::mobileiron - Web form for mobileiron provisioner

=head1 DESCRIPTION

=cut

use HTML::FormHandler::Moose;
extends 'pfappserver::Form::ConfigStore::Provisioning';
with 'pfappserver::Base::Form::Role::Help';

has_field username => (
    type => 'Text',
    required => 1,
);

has_field password => (
    type => 'Password',
    required => 1,
    password => 0,
);

has_field host => (
    type => 'Text',
    required => 1,
);

has_field android_download_uri => (
    type => 'Text',
);

has_field ios_download_uri => (
    type => 'Text',
);

has_field windows_phone_download_uri => (
    type => 'Text',
);

has_field boarding_host => (
    type => 'Text',
);

has_field boarding_port => (
    type => 'Text',
);

has_block definition =>
  (
   render_list => [ qw(id type description username password host android_download_uri ios_download_uri windows_phone_download_uri boarding_host boarding_port) ],
  );

=head1 COPYRIGHT

Copyright (C) 2014 Inverse inc.

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

__PACKAGE__->meta->make_immutable;
1;
