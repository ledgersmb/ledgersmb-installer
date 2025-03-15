package LedgerSMB::Installer;

use v5.34;
use experimental qw(signatures try);

use Carp qw( croak );
use CPAN::Meta::Requirements;
use File::Path qw( make_path remove_tree );
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use HTTP::Tiny;
use IO::Handle;
use JSON::PP;

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
    my @unmapped;
    for my $mod (@mods) {
        my $pkg = $dss->pkg_from_module( $mod );

        if ($pkg) {
            $pkgs{$pkg} = 1;
        }
        else {
            push @unmapped, $mod;
        }
    }
    delete $pkgs{perl};

    return ([ sort keys %pkgs ], \@unmapped);
}

sub _download($class, $installpath, $version) {
    my $fn   = "ledgersmb-$version.tar.gz";
    my $url  = $ENV{ARTIFACT_LOCATION} // "https://download.ledgersmb.org/f/Releases/$version/";
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

sub _load_dist_support($class) {
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

    my $oss = $oss_class->new; # operating system support instance
    $log->debug( "Detecting distribution" );
    return $oss->detect_dss; # detect and return distribution support instance
}

sub compute($class, @args) {
    my $dss = $class->_load_dist_support;
    my $config = LedgerSMB::Installer::Configuration->new;

    GetOptionsFromArray(
        \@args,
        'yes|y!'             => sub { $config->assume_yes( $_[1] ) },
        'target=s'           => sub { $config->installpath( $_[1] ) },
        'local-lib=s'        => sub { $config->locallib( $_[1] ) },
        'log-level=s'        => sub { $config->loglevel( $_[1] ) },
        'version=s'          => sub { $config->version( $_[1] ) },
        );

    # normalize $installpath (at least cpanm needs that)
    # assume $locallib to be inside $installpath
    $config->normalize_paths;

    Log::Any::Adapter->set('Stdout', log_level => $config->loglevel);

    if (@args != 1) {
        die "Incorrect number of arguments";
    }
    open( my $out, '>:encoding(UTF-8)', $args[0] )
        or die "Unable to open output file '$args[0]': $!";

    if ($config->effective_prepare_env) {
        $dss->prepare_env(
            $config,
            compute_deps => 1,
            );
    }

    my $exception;
    try {
        my @remarks = $dss->validate_env(
            $config,
            compute_deps => 1,
            );

        $class->_build_install_tree( $dss, $config->installpath, $config->version );

        $log->info( "Computing O/S packages for declared dependencies" );
        my ($deps, $mods) = $class->_compute_dep_pkgs( $dss, $config->installpath );

        my $json = JSON::PP->new->utf8->canonical;
        say $out $json->encode( { identifier => $dss->dependency_packages_identifier,
                                  packages => $deps,
                                  modules => $mods,
                                  name => $dss->name,
                                  version => "1" } );
    }
    catch ($e) {
        $exception = $e;
    }
    finally {
        if ($config->effective_uninstall_env) {
            $log->warning( "Cleaning up Perl module installation dependencies" );
            $dss->cleanup_env($config);
        }
    }

    die $exception if $exception;

    return 0;
}

sub download($class, @args) {
}

sub install($class, @args) {
    my $dss = $class->_load_dist_support;
    my $config = LedgerSMB::Installer::Configuration->new(
        sys_pkgs => $dss->pkg_can_install,
        );

    GetOptionsFromArray(
        \@args,
        'yes|y!'             => sub { $config->assume_yes( $_[1] ) },
        'system-packages!'   => sub { $config->sys_pkgs( $_[1] ) },
        'prepare-env!'       => sub { $config->prepare_env( $_[1] ) },
        'target=s'           => sub { $config->installpath( $_[1] ) },
        'local-lib=s'        => sub { $config->locallib( $_[1] ) },
        'log-level=s'        => sub { $config->loglevel( $_[1] ) },
        'verify-sig!'        => sub { $config->verify_sig( $_[1] ) },
        'version=s'          => sub { $config->version( $_[1] ) },
        );

    # normalize $installpath (at least cpanm needs that)
    # assume $locallib to be inside $installpath
    $config->normalize_paths;

    Log::Any::Adapter->set('Stdout', log_level => $config->loglevel);

    my $deps;
    do {
        my $name = $dss->name;
        my $dep_pkg_id = $dss->dependency_packages_identifier;
        if ($config->sys_pkgs) {
            $deps = $config->retrieve_precomputed_deps($name, $dep_pkg_id);
        }
        unless ($deps) {
            $log->warn( "No precomputed dependencies available for $name/$dep_pkg_id" );
            $log->info( "Configuring environment for dependency computation" );
        }
    };

    if ($config->effective_prepare_env) {
        $dss->prepare_env(
            $config,
            compute_deps => $config->effective_compute_deps,
            install_deps => $config->sys_pkgs,
            install_mods => 1
            );
    }

    my $exception;
    try {
        my @remarks = $dss->validate_env(
            $config,
            compute_deps => $config->effective_compute_deps,
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

        if ($config->effective_compute_deps) {
            $log->info( "Computing O/S packages for declared dependencies" );

            # discard unmapped modules
            ($deps) = $class->_compute_dep_pkgs( $dss, $config->installpath );
        }

        if ($deps and $config->sys_pkgs) {
            $log->info( "Installing O/S packages: " . join(' ', $deps->@*) );
            $dss->pkg_install( $deps )
        }
        $dss->cpanm_install( $config->installpath, $config->locallib );
        $dss->generate_startup( $config );
    }
    catch ($e) {
        $exception = $e;
    }
    finally {
        if ($config->effective_uninstall_env) {
            $log->warning( "Cleaning up Perl module installation dependencies" );
            $dss->cleanup_env($config);
        }
    }

    die $exception if $exception;

    return 0;
}

sub print_id( $class, @args) {
    my $dss = $class->_load_dist_support;
    say $dss->dependency_packages_identifier;
}

sub run($class, $cmd, @args) {
    STDOUT->autoflush(1);
    STDERR->autoflush(1);

    if ($cmd =~ m/^-/) { # option(s)
        unshift @args, $cmd;
        $cmd = 'install';
    }
    elsif ($cmd eq 'compute') {
        return $class->compute( @args );
    }
    elsif ($cmd eq 'download') {
        return $class->download( @args );
    }
    elsif ($cmd eq 'install') {
        return $class->install( @args );
    }
    elsif ($cmd eq 'system-id') {
        return $class->print_id( @args );
    }
    else {
        die "Unknown command 'cmd'\n";
    }
}


1;
