package LedgerSMB::Installer;

use v5.34;
use experimental qw(signatures try);

use Carp qw( croak );
use CPAN::Meta::Requirements;
use File::Path qw( make_path remove_tree );
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use HTTP::Tiny;

use Log::Any qw($log);
use Log::Any::Adapter;
use Module::CPANfile;

use LedgerSMB::Installer::Configuration;

sub _build_install_tree($class, $dss, $installpath, $version) {
    my $archive = "ledgersmb-$version.tar.gz";

    $log->info( "Creating installation path $installpath" );
    make_path( $installpath ); # croaks on fatal errors

    $log->info( "Downloading release tarball $archive" );
    $class->_download( $installpath, $version );

    #$log->info( "Verifying tarball against gpg public key & signature" );
    #$dss->verify_gpg( \@cmds, $archive )
    #    if $verify;

    $log->info( "Extracting release tarball" );
    $dss->untar( File::Spec->catfile( $installpath, $archive),
                 $installpath,
                 strip_components => 1 );

    $log->info( "Removing extracted release tarball" );
    remove_tree(               # croaks on fatal errors
        map {
            File::Spec->catfile( $installpath, $_ )
        } ( $archive, "$archive.asc" ) );
}

sub _compute_dep_pkgs($class, $dss, $installpath) {
    my @types     = qw( requires recommends );
    my @phases    = qw( runtime );
    my $decl      = Module::CPANfile->load( File::Spec->catfile( $installpath, 'cpanfile' ) );
    my $prereqs   = $decl->prereqs_with( map { $_->identifier } $decl->features ); # all features
    my $effective = CPAN::Meta::Requirements->new;
    for my $phase (@phases) {
        for my $type (@types) {
            $effective->add_requirements( $prereqs->requirements_for( $phase, $type ) );
        }
    }

    my @mods = sort { lc($a) cmp lc($b) } $effective->required_modules;
    my %pkgs;
    for my $mod (@mods) {
        my $pkg = $dss->pkg_from_module( $mod );
        $pkgs{$pkg} = 1 if $pkg;
    }
    delete $pkgs{perl};

    return keys %pkgs;
}

sub _download($class, $installpath, $version) {
    my $fn   = "ledgersmb-$version.tar.gz";
    my $url  = $ENV{ARTEFACT_LOCATION} // "https://download.ledgersmb.org/f/Releases/$version/";
    my $http = HTTP::Tiny->new;

    do {
        open( my $fh, '>', File::Spec->catfile($installpath, $fn))
            or croak $log->fatal( "Unable to open output file $fn: $!" );
        binmode $fh, ':raw';
        my $r = $http->get(
            "$url$fn",
            {
                data_callback => sub($data, $status) {
                    print $fh $data;
                }
            });

        if ($r->{status} == 599) {
            croak $log->fatal( "Unable to request $url/$fn: " . $r->{content} );
        }
        elsif (not $r->{success}) {
            croak $log->fatal( "Unable to request $url/$fn: $r->{status} - $r->{reason}" );
        }
    };

    do {
        my $r = $http->get( "$url$fn.asc" );
        if ($r->{status} == 599) {
            croak $log->fatal( "Unable to request $url/$fn: " . $r->{content} );
        }
        elsif (not $r->{success}) {
            croak $log->fatal( "Unable to request $url/$fn: $r->{status} - $r->{reason}" );
        }
        else {
            open( my $fh, '>', File::Spec->catfile($installpath, "$fn.asc"))
                or croak $log->fatal( "Unable to open output file $fn.asc: $!" );
            binmode $fh, ':raw';
            print $fh $r->{content};
        }
    };
}

sub compute($class, @args) {
}

sub download($class, @args) {
}

sub install($class, @args) {
    my $verify = 1;
    my $locallib = 'local';
    my $installpath = 'ledgersmb';
    my $syspkgs = 1;
    my $config = LedgerSMB::Installer::Configuration->new(
        # defaults:
        installpath => 'ledgersmb',
        locallib => 'local',
        loglevel => 'info',
        );

    GetOptionsFromArray(
        \@args,
        'system-packages!'   => \$syspkgs,
        'target=s'           => sub { $config->installpath( $_[1] ) },
        'local-lib=s'        => sub { $config->locallib( $_[1] ) },
        'log-level=s'        => sub { $config->loglevel( $_[1] ) },
        'verify!'            => \$verify,
        'version=s'          => sub { $config->version( $_[1] ) },
        );

    Log::Any::Adapter->set('Stdout', log_level => $config->loglevel);

    # normalize $installpath (at least cpanm needs that)
    # assume $locallib to be inside $installpath
    $config->normalize_paths;

    $log->info( "Detected O/S: $^O" );
    my $oss_class = "LedgerSMB::Installer::OS::$^O";
    try {
        eval "require $oss_class"
            or die "Unable to load $oss_class: $@";
    }
    catch ($e) {
        say "$e";
        say "No support for $^O";
        exit 2;
    }

    my $oss = $oss_class->new( config => $config ); # operating system support instance
    $log->debug( "Detecting distribution" );
    my $dss = $oss->detect_dss(); # detect and return distribution support instance

    my $deps;
    $deps = $dss->retrieve_precomputed_deps
        if $syspkgs;
    unless ($deps) {
        $log->warn( "No precomputed dependencies available for this distro/version" );
        $log->info( "Configuring environment for dependency computation" );
    }

    my @remarks = $dss->validate_env(
        compute_deps => defined($deps),
        install_deps => 1,
        );

    # Generate script
    # 1. build install path:
    #    a. create installation directory
    #    b. download tarball
    #    c. unpack tarball
    #    d. delete tarball
    # in case of missing precomputed deps:
    #   5. compute dependencies (distro packages)
    # 6. install (pre)computed dependencies (distro packages)
    # 7. install CPAN dependencies (using cpanm & local::lib)
    # 8. generate startup script (set local::lib environment)

    $class->_build_install_tree( $dss, $config->installpath, $config->version );

    if (not $deps
        and $dss->{_have_pkgs}) {
        $log->info( "Computing O/S packages for declared dependencies" );
        $deps = [ $class->_compute_dep_pkgs( $dss, $config->installpath ) ];
    }

    if ($deps and $dss->{_have_pkgs}) {
        $log->info( "Installing O/S packages: " . join(' ', $deps->@*) );
        $dss->pkg_install( $deps )
    }
    $dss->cpanm_install( $config->installpath, $config->locallib );
    $dss->generate_startup( $config->installpath, $config->locallib );

    return 0;
}

sub run($class, $cmd, @args) {
    if ($cmd =~ m/^-/) { # option(s)
        unshift @args, $cmd;
        $cmd = 'install';
    }
    if ($cmd eq 'compute') {
        return $class->compute( @args );
    }
    elsif ($cmd eq 'download') {
        return $class->download( @args );
    }
    if ($cmd eq 'install') {
        return $class->install( @args );
    }
    else {
        die "Unknown command 'cmd'\n";
    }
}


1;
