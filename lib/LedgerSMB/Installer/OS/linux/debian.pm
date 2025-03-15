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
        _distro => $args{distro},
    }, $class;
}

sub name($self) {
    return $self->{_distro}->{ID};
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

sub pkg_can_install($self) {
    return ($EFFECTIVE_USER_ID == 0);
}

sub pkg_install($self, $pkgs) {
    $pkgs //= [];
    my $apt_get = $self->have_cmd( 'apt-get' );
    my $cmd;
    $cmd = "DEBIAN_FRONTEND=noninteractive $apt_get update -q -y";
    $log->debug( "system(): " . $cmd );
    system($cmd) == 0
        or croak $log->fatal( "Unable to update 'apt-get' package index: $!" );

    $cmd = "DEBIAN_FRONTEND=noninteractive $apt_get install -q -y " . join(' ', $pkgs->@*);
    $log->debug( "system(): " . $cmd );
    system($cmd) == 0
        or croak $log->fatal( "Unable to install required packages through apt-get: $!" );
}

sub pkg_uninstall($self, $pkgs) {
    $pkgs //= [];
    my $apt_get = $self->have_cmd( 'apt-get' );
    my $cmd = "DEBIAN_FRONTEND=noninteractive $apt_get autoremove --purge -q -y " . join(' ', $pkgs->@*);
    $log->debug( "system(): " . $cmd );
    system($cmd) == 0
        or croak $log->fatal( "Unable to uninstall packages through apt-get: $!" );
}

sub cleanup_env($self, $config) {
    $self->pkg_uninstall( [ $config->pkgs_for_cleanup ] );
}

sub prepare_env($self, $config, %args) {
    my @pkgs = ();

    $log->debug( "Preparing environment for 'debian'" );
    if ($args{compute_deps}) {
        $log->trace( "Preparing for dependency computation" );
        push @pkgs, 'apt-file' unless $self->have_cmd( 'apt-file', 0 );
        push @pkgs, 'dh-make-perl' unless $self->have_cmd( 'dh-make-perl', 0 );
    }
    if ($args{install_mods}) {
        $log->trace( "Preparing for module installation" );
        push @pkgs, 'gcc' unless $self->have_cmd( 'gcc', 0 );
        push @pkgs, 'make' unless $self->have_cmd( 'make', 0 );
    }

    if (@pkgs) {
        $config->mark_pkgs_for_cleanup( \@pkgs );
        $self->pkg_install( \@pkgs );
    }
}

sub validate_env($self, $config, %args) {
    my ($install_deps, $compute_deps) = @args{qw(install_deps compute_deps)};
    $self->SUPER::validate_env(
        $config,
        %args,
        );
    $self->have_cmd( 'dpkg',         1 );                              # dpkg --print-architecture
    $self->have_cmd( 'apt-get',      $config->sys_pkgs );
    $self->have_cmd( 'apt-file',     $config->effective_compute_deps );
    $self->have_cmd( 'dh-make-perl', $config->effective_compute_deps );
}

1;
