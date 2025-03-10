package LedgerSMB::Installer::OS::linux::debian;

use v5.34;
use experimental qw( try signatures );
use parent qw( LedgerSMB::Installer::OS::linux );

use Carp qw( croak );
use English;
use HTTP::Tiny;
use JSON::PP;

use Log::Any qw($log);

sub new($class, %args) {
    return bless {
        _config => $args{config},
        _distro => $args{distro},
        _have_deps => 0,
        _have_pkgs => ($EFFECTIVE_USER_ID == 0),
    }, $class;
}

sub retrieve_precomputed_deps($self) {
    my $http = HTTP::Tiny->new;
    my $arch = `dpkg --print-architecture`;
    chomp($arch);
    my $url  = $self->{_config}->dependency_url(
        $self->{_distro}->{ID},
        $self->dependency_packages_identifier
        );

    $log->info( "Retrieving dependency listing from $url" );
    my $r = $http->get( $url );
    if ($r->{success}) {
        $self->{_have_deps} = 1;
        return JSON::PP->new->utf8->decode( $r->{content} )->{packages};
    }
    elsif ($r->{status} == 599) {
        die $log->fatal(
            'Error trying to retrieve precomputed dependencies: ' . $r->{content}
            );
    }
    return;
}

sub dependency_packages_identifier($self) {
    my $arch = `dpkg --print-architecture`;
    chomp($arch);
    return "$self->{_distro}->{ID}-$self->{_distro}->{VERSION_CODENAME}-$arch";
}

sub pkg_from_module( $self, $mod ) {
    if (not state $init = 0) {
        $log->info( "Updating 'apt-file' packages index" );
        system($self->{cmd}->{'apt-file'}, 'update') == 0
            or croak $log->fatal( "Unable to update apt-file's index: $!" );
        $init = 1;
    }
    $log->debug( "Looking up package for $mod" );
    my $pkg = `$self->{cmd}->{'dh-make-perl'} --no-verbose locate "$mod" 2>/dev/null`;
    if ($?) {
        return '';
    }
    elsif ($pkg =~ m/is not found in any/) {
        return '';
    }
    elsif ($pkg =~ m/is in (\S+) package/) {
        my $rv = $1;
        $log->trace( "Module '$mod' found in package $1" );
        return $rv;
    }
    return '';
}

sub pkg_install($self, $pkgs) {
    $pkgs //= [];
    my $cmd;
    $cmd = "DEBIAN_FRONTEND=noninteractive $self->{cmd}->{'apt-get'} update -q -y";
    $log->debug( "system(): " . $cmd );
    system($cmd) == 0
        or croak $log->fatal( "Unable to update 'apt-get' package index: $!" );

    $cmd = "DEBIAN_FRONTEND=noninteractive $self->{cmd}->{'apt-get'} install -q -y " . join(' ', $pkgs->@*);
    $log->debug( "system(): " . $cmd );
    system($cmd) == 0
        or croak $log->fatal( "Unable to install required packages through apt-get: $!" );
}

sub validate_env($self, %args) {
    $self->SUPER::validate_env(
        %args,
        );
    $self->have_cmd( 'dpkg', 1 ); # dpkg --print-architecture
    $self->have_cmd( 'apt-get', 1 ); # required to install dependencies
    $self->have_cmd( 'apt-file', not $self->{_have_deps} ); # required for computation of dependencies
    $self->have_cmd( 'dh-make-perl', not $self->{_have_deps} );
}

1;
