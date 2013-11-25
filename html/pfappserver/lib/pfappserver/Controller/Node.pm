package pfappserver::Controller::Node;

=head1 NAME

pfappserver::Controller::Node - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

use strict;
use warnings;

use HTTP::Status qw(:constants is_error is_success);
use Moose;
use namespace::autoclean;
use POSIX;

use pfappserver::Form::Node;
use pfappserver::Form::Node::Create::Import;

BEGIN { extends 'pfappserver::Base::Controller'; }
with 'pfappserver::Role::Controller::BulkActions';

__PACKAGE__->config(
    action_args => {
        '*' => { model => 'Node' },
        advanced_search => { model => 'Search::Node', form => 'AdvancedSearch' },
    }
);

=head1 SUBROUTINES


=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;
    $c->go('simple_search');
}

=head2 simple_search

=cut

sub simple_search :SimpleSearch('Node') :Local :Args() { }

=head2 after _list_items

The method _list_items comes from pfappserver::Base::Controller and is called from Base::Action::SimpleSearch.

=cut

after _list_items => sub {
    my ($self, $c) = @_;

    my ( $status, $roles, $violations );
    ($status,$roles) = $c->model('Roles')->list();
    $c->stash(roles => $roles);
    ( $status, $violations ) = $c->model('Config::Violations')->readAll();
    $c->stash( violations => $violations );

    unless ($c->session->{'nodecolumns'}) {
        # Set default visible columns
        my %default_columns = map { $_ => 1 } qw/status mac computername pid last_ip dhcp_fingerprint category/;
        $c->session( nodecolumns => \%default_columns );
    }
};


=head2 advanced_search

Perform an advanced search using the Search::Node model

=cut

sub advanced_search :Local :Args() {
    my ($self, $c, @args) = @_;
    my ($status, $status_msg, $result, $violations);
    my %search_results;
    my $model = $self->getModel($c);
    my $form = $self->getForm($c);

    # Store columns in the session
    my $columns = $c->request->params->{'column'};
    if ($columns) {
        $columns = [$columns] if (ref($columns) ne 'ARRAY');
        my %columns_hash = map { $_ => 1 } @{$columns};
        my %params = ( 'nodecolumns' => \%columns_hash );
        $c->session(%params);
    }

    $form->process(params => $c->request->params);
    if ($form->has_errors) {
        $status = HTTP_BAD_REQUEST;
        $status_msg = $form->field_errors;
        $c->stash(current_view => 'JSON');
    }
    else {
        my $query = $form->value;
        $query->{by} = 'mac' unless ($query->{by});
        $query->{direction} = 'asc' unless ($query->{direction});
        ($status, $result) = $model->search($query);
        if (is_success($status)) {
            $c->stash(form => $form);
            $c->stash($result);
        }
    }

    (undef, $result) = $c->model('Roles')->list();
    (undef, $violations ) = $c->model('Config::Violations')->readAll();
    $c->stash(
        status_msg => $status_msg,
        roles => $result,
        violations => $violations,
    );
    $c->response->status($status);
}

=head2 create

Create one node or import a CSV file.

=cut

sub create :Local {
    my ($self, $c) = @_;

    my ($roles, $node_status, $form_single, $form_import, $params, $type);
    my ($status, $result, $message);

    ($status, $result) = $c->model('Roles')->list();
    if (is_success($status)) {
        $roles = $result;
    }
    $node_status = $c->model('Node')->availableStatus();

    $form_single = pfappserver::Form::Node->new(ctx => $c, status => $node_status, roles => $roles);
    $form_import = pfappserver::Form::Node::Create::Import->new(ctx => $c, roles => $roles);

    if (scalar(keys %{$c->request->params}) > 1) {
        # We consider the request parameters only if we have at least two entries.
        # This is the result of setuping jQuery in "no Ajax cache" mode. See admin/common.js.
        $params = $c->request->params;
    } else {
        $params = {};
    }
    $form_single->process(params => $params);

    if ($c->request->method eq 'POST') {
        # Create new nodes
        $type = $c->request->param('type');
        if ($type eq 'single') {
            if ($form_single->has_errors) {
                $status = HTTP_BAD_REQUEST;
                $message = $form_single->field_errors;
            }
            else {
                ($status, $message) = $c->model('Node')->create($form_single->value);
            }
        }
        elsif ($type eq 'import') {
            my $params = $c->request->params;
            $params->{nodes_file} = $c->req->upload('nodes_file');
            $form_import->process(params => $params);
            if ($form_import->has_errors) {
                $status = HTTP_BAD_REQUEST;
                $message = $form_import->field_errors;
            }
            else {
                ($status, $message) = $c->model('Node')->importCSV($form_import->value, $c->user);
                if (is_success($status)) {
                    $message = $c->loc("[_1] nodes imported, [_2] skipped", $message->{count}, $message->{skipped});
                }
            }
        }
        else {
            $status = $STATUS::INTERNAL_SERVER_ERROR;
        }

        $c->response->status($status);
        $c->stash->{status} = $status;
        $c->stash->{status_msg} = $message; # TODO: localize error message
        $c->stash->{current_view} = 'JSON';
    }
    else {
        # Initial display of the page
        $form_import->process();

        $c->stash->{form_single} = $form_single;
        $c->stash->{form_import} = $form_import;
    }
}

=head2 object

Node controller dispatcher

=cut

sub object :Chained('/') :PathPart('node') :CaptureArgs(1) {
    my ( $self, $c, $mac ) = @_;

    my ($status, $node_ref, $roles_ref);

    ($status, $node_ref) = $c->model('Node')->exists($mac);
    if ( is_error($status) ) {
        $c->response->status($status);
        $c->stash->{status_msg} = $node_ref;
        $c->stash->{current_view} = 'JSON';
        $c->detach();
    }
    ($status, $roles_ref) = $c->model('Roles')->list();
    if (is_success($status)) {
        $c->stash->{roles} = $roles_ref;
    }

    $c->stash->{mac} = $mac;
}

=head2 view

=cut

sub view :Chained('object') :PathPart('read') :Args(0) {
    my ($self, $c) = @_;

    my ($nodeStatus, $result);
    my ($form, $status);

    # Form initialization :
    # Retrieve node details and status

    ($status, $result) = $c->model('Node')->view($c->stash->{mac});
    if (is_success($status)) {
        $c->stash->{node} = $result;
    }
    ($status, $result) = $c->model('Config::Switch')->readAll();
    if (is_success($status)) {
        my %switches = map { $_->{id} => { type => $_->{type},
                                           mode => $_->{mode} } } @$result;
        $c->stash->{switches} = \%switches;
    }
    $nodeStatus = $c->model('Node')->availableStatus();
    $form = $c->form("Node",
                     init_object => $c->stash->{node},
                     status => $nodeStatus,
                     roles => $c->stash->{roles}
    );
    $form->process();
    $c->stash->{form} = $form;

#    my @now = localtime;
#    $c->stash->{now} = { date => POSIX::strftime("%Y-%m-%d", @now),
#                         time => POSIX::strftime("%H:%M", @now) };
}

=head2 update

=cut

sub update :Chained('object') :PathPart('update') :Args(0) {
    my ( $self, $c ) = @_;

    my ($status, $message);
    my ($form, $nodeStatus);

    $nodeStatus = $c->model('Node')->availableStatus();
    $form = $c->form("Node",
                     status => $nodeStatus,
                     roles => $c->stash->{roles}
    );
    $form->process(params => { mac => $c->stash->{mac}, %{$c->request->params} });
    if ($form->has_errors) {
        $status = HTTP_BAD_REQUEST;
        $message = $form->field_errors;
    }
    else {
        ($status, $message) = $c->model('Node')->update($c->stash->{mac}, $form->value);
    }
    if (is_error($status)) {
        $c->response->status($status);
        $c->stash->{status_msg} = $message; # TODO: localize error message
    }
    $c->stash->{current_view} = 'JSON';
}

=head2 delete

=cut

sub delete :Chained('object') :PathPart('delete') :Args(0) {
    my ( $self, $c ) = @_;

    my ($status, $message) = $c->model('Node')->delete($c->stash->{mac});
    if (is_error($status)) {
        $c->response->status($status);
        $c->stash->{status_msg} = $message; # TODO: localize error message
    }
    $c->stash->{current_view} = 'JSON';
}

=head2 violations

=cut

sub violations :Chained('object') :PathPart :Args(0) {
    my ($self, $c) = @_;
    my ($status, $result) = $c->model('Node')->violations($c->stash->{mac});
    if (is_success($status)) {
        $c->stash->{items} = $result;
        $c->stash->{template} = 'node/violations.tt';
        (undef, $result) = $c->model('Config::Violations')->readAll();
        my @violations = grep { $_->{id} ne 'defaults' } @$result; # remove defaults
        $c->stash->{violations} = \@violations;
    }
    else {
        $c->response->status($status);
        $c->stash->{status_msg} = $result;
        $c->stash->{current_view} = 'JSON';
    }
}

=head2 triggerViolation

=cut

sub triggerViolation :Chained('object') :PathPart('trigger') :Args(1) {
    my ($self, $c, $id) = @_;
    my ($status, $result) = $c->model('Config::Violations')->hasId($id);
    if (is_success($status)) {
        ($status, $result) = $c->model('Node')->addViolation($c->stash->{mac}, $id);
    }
    $c->response->status($status);
    $c->stash->{status_msg} = $result;
    if (is_success($status)) {
        $c->forward('violations');
    }
    else {
        $c->stash->{current_view} = 'JSON';
    }
}

=head2 closeViolation

=cut

sub closeViolation :Path('close') :Args(1) {
    my ($self, $c, $id) = @_;
    my ($status, $result) = $c->model('Node')->closeViolation($id);
    $c->response->status($status);
    $c->stash->{status_msg} = $result;
    $c->stash->{current_view} = 'JSON';
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2012-2013 Inverse inc.

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
