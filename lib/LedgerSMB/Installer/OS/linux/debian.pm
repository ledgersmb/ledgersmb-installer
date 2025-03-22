package LedgerSMB::Installer::OS::linux::debian;

use v5.20;
use experimental qw(signatures);
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

sub pkgs_from_modules($self, $mods) {
    if (not state $init = 0) {
        $log->info( "Updating 'apt-file' packages index" );
        system($self->{cmd}->{'apt-file'}, 'update') == 0
            or croak $log->fatal( "Unable to update apt-file's index: $!" );
        $init = 1;
    }

    my $args = join(' ', $mods->@*);
    open(my $fh, '-|',
         "$self->{cmd}->{'dh-make-perl'} --no-verbose locate $args 2>/dev/null")
        or return ({}, []);

    my (%pkgs, @unmapped);
    while (my $pkg_line = <$fh>) {
        if ($pkg_line =~ m/^(\S+) is not found in any/) {
            push @unmapped, $1;
            $log->trace( "Module '$1' not found" );
        }
        elsif ($pkg_line =~ m/^(\S+) is in (\S+) package/) {
            $pkgs{$2} //= [];
            push $pkgs{$2}->@*, $1;
            $log->trace( "Module '$1' found in package $2" );
        }
    }
    return (\%pkgs, \@unmapped);
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

sub cleanup_env($self, $config, %args) {
    if ($args{compute_deps}) {
        # this is rather ugly; better to have prepare_env to schedule the right packages...
        $self->pkg_uninstall( [ grep { m/^(?:apt-file|dh-make-perl)$/ }
                                $config->pkgs_for_cleanup ] );
        return;
    }

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
