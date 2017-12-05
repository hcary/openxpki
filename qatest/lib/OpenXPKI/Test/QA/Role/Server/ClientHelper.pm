package OpenXPKI::Test::QA::Role::Server::ClientHelper;
use Moose;
use utf8;

=head1 NAME

OpenXPKI::Test::QA::Role::Server::ClientHelper - Helper functions to test
OpenXPKI client talking to a running (test) server

=cut

# Core modules
use Test::More;
use Test::Exception;

# CPAN modules

# Project modules
use OpenXPKI::Client;

=head1 DESCRIPTION

=cut

has socket_file => (
    is => 'rw',
    does => 'Str',
    required => 1,
);

has default_realm => (
    is => 'rw',
    does => 'Str',
    required => 1,
);

# password for all test users
has password => (
    is => 'rw',
    does => 'Str',
    required => 1,
);

has client => (
    is => 'rw',
    isa => 'OpenXPKI::Client',
    init_arg => undef,
    predicate => 'is_connected',
);

has response => (
    is => 'rw',
    isa => 'HashRef',
    init_arg => undef,
);

=head1 METHODS

=cut
sub connect {
    my $self = shift;

    return if $self->is_connected;

    lives_ok {
        # instantiating the client means starting it as all initialization is
        # done in the constructor
        $self->client(
            OpenXPKI::Client->new({
                TIMEOUT => 5,
                SOCKETFILE => $self->socket_file,
            })
        );
    } "create client instance" or BAIL_OUT "Could not create client instance";
}

sub init_session {
    my ($self, $args) = @_;

    $self->connect;

    lives_and {
        $self->response($self->client->init_session($args));
        $self->is_next_step(($args and $args->{'SESSION_ID'}) ? "SERVICE_READY" : "GET_PKI_REALM");
    } "initialize client session";
}

sub login {
    my ($self, $user) = @_;

    $self->init_session unless ($self->is_connected and $self->client->get_session_id);

    subtest "client login" => sub {
        plan tests => 6;

        $self->send_ok('GET_PKI_REALM', { PKI_REALM => $self->default_realm });
        $self->is_next_step("GET_AUTHENTICATION_STACK");

        $self->send_ok('GET_AUTHENTICATION_STACK', { AUTHENTICATION_STACK => "Test" });
        $self->is_next_step("GET_PASSWD_LOGIN");

        $self->send_ok('GET_PASSWD_LOGIN', { LOGIN => $user, PASSWD => $self->password });
        $self->is_next_step("SERVICE_READY");
    }
}

sub is_next_step {
    my ($self, $step) = @_;
    ok $self->is_service_msg($step), "<< server expects $step"
        or diag explain $self->response;
}

sub send_ok {
    my ($self, $msg, $args) = @_;
    lives_and {
        $self->response($self->client->send_receive_service_msg($msg, $args));
        if (my $err = $self->get_error) {
            diag $err;
            fail;
        }
        else {
            pass;
        }
    } ">> send $msg".($msg eq "COMMAND" ? ": ".$args->{COMMAND} : "");

    return $self->response->{PARAMS};
}

sub send_command_ok {
    my ($self, $command, $params) = @_;
    return $self->send_ok('COMMAND', { COMMAND => $command, PARAMS => $params });
}

sub is_service_msg {
    my ($self, $msg) = @_;
    return unless $self->response;
    return unless exists $self->response->{SERVICE_MSG};
    return $self->response->{SERVICE_MSG} eq $msg;
}

sub get_error {
    my $self = shift;
    if ($self->is_service_msg('ERROR')) {
        return $self->response->{LIST}->[0]->{LABEL} || 'Unknown error';
    }
    return;
}

__PACKAGE__->meta->make_immutable;
