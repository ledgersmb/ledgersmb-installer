package LedgerSMB::Installer::OS::linux::fedora;

use v5.20;
use experimental qw(signatures);
use parent qw( LedgerSMB::Installer::OS::linux );

use Carp qw( croak );
use English;
use HTTP::Tiny;
use JSON::PP;

use Log::Any qw($log);

# dnf repoquery --installed --queryformat '%{name}\n' <packages>
# dnf group list --installed

sub new($class, %args) {
    return bless {
        _distro => $args{distro},
    }, $class;
}

sub name($self) {
    return $self->{_distro}->{ID};
}

sub dependency_packages_identifier($self) {
    my $arch;
    if (my $dnf5 = $self->have_cmd( 'dnf5' )) {
        (undef, $arch) = split(/ *= */, `'$dnf5' --dump-variables 2>/dev/null | grep 'basearch = '`);
    }
    else {
        $arch = `python3 -c 'import dnf; print(dnf.Base().conf.basearch)'`;
    }

    chomp($arch);
    return "$self->{_distro}->{ID}-$self->{_distro}->{VERSION_CODENAME}-$arch";
}

sub pkgs_from_modules($self, $mods) {
    my (%pkgs, @unmapped);
    my $dnf = $self->have_cmd( 'dnf' );
    while (my $mod = shift $mods->@*) {
        my $pkg = `'$dnf' repoquery --whatprovides 'perl($mod)' --queryformat '%{name}' 2>/dev/null`;
        chomp($pkg);
        if ($pkg) {
            $pkgs{$pkg} //= [];
            push $pkgs{$pkg}->@*, $mod;
            $log->trace( "Module '$mod' found in package $pkg" );
        }
        else {
            push @unmapped, $mod;
            $log->trace( "Module '$mod' not found" );
        }
    }
    return (\%pkgs, \@unmapped);
}

sub pkg_can_install($self) {
    return ($EFFECTIVE_USER_ID == 0);
}

sub pkg_install($self, $pkgs) {
    $pkgs //= [];
    my $dnf = $self->have_cmd( 'dnf' );
    my $cmd;
    $cmd = "'$dnf' install -q -y " . join(' ', $pkgs->@*);
    $log->debug( "system(): " . $cmd );
    system($cmd) == 0
        or croak $log->fatal( "Unable to install required packages through dnf: $!" );
}

sub pkg_uninstall($self, $pkgs) {
    $pkgs //= [];
    my $dnf = $self->have_cmd( 'dnf' );
    my $cmd = "'$dnf' remove -q -y " . join(' ', $pkgs->@*);
    $log->debug( "system(): " . $cmd );
    system($cmd) == 0
        or croak $log->fatal( "Unable to uninstall packages through dnf: $!" );
}

sub cleanup_env($self, $config, %args) {
    $self->pkg_uninstall( [ $config->pkgs_for_cleanup ] );
}

sub prepare_builder_environment($self, $config) {
    my $dnf = $self->have_cmd( 'dnf' );
    my $have_c_development = `'$dnf' group list --installed | grep '^c-development'`;
    unless ($? == 0) {
        $config->mark_pkgs_for_cleanup( [ '@c-development' ] );
        $self->pkg_install( [ '@c-development' ] );
    }
}

sub prepare_installer_environment($self, $config) {
    my $dnf = $self->have_cmd( 'dnf' );
    my $have_make = `'$dnf' repoquery --installed --queryformat '%{name}' make`;
    unless ($? == 0) {
        $config->mark_pkgs_for_cleanup( [ 'make' ] );
        $self->pkg_install( [ 'make' ] );
    }
    $self->SUPER::prepare_installer_environment( $config );
}

sub prepare_pkg_resolver_environment($self, $config) {
    $self->have_cmd( 'dnf',     $config->effective_compute_deps );
}

sub _rm_installed($pkgs) {
    my %pkgs = map {
        $_ => 1
    } $pkgs->@*;
    my $dnf = $self->have_cmd( 'dnf' );
    my $cmd = qq{'$dnf' repoquery --installed --queryformat '%{name}\\n' } . join(' ', $pkgs->@*);
    my $installed = `$cmd`;
    delete $pkgs{$_} for (split( /\n/, $installed ));

    return [ keys %pkgs ];
}

sub pkg_deps_latex($self) {
    return (_rm_installed([ qw(texlive-latex texlive-plain texlive-xetex) ]),
            []);
}

sub pkg_deps_xml($self) {
    return (_rm_installed([ qw(libxml2) ]),
            _rm_installed([ qw(libxml2-devel) ]));
}

sub pkg_deps_expat($self) {
    return (_rm_installed([ qw(expat) ]),
            _rm_installed([ qw(expat-devel) ]));
}

sub pkg_deps_dbd_pg($self) {
    return (_rm_installed([ qw(libpq) ]),
            _rm_installed([ qw(libpq-devel) ]));
}

1;
