package LedgerSMB::Installer;

use v5.20;
use experimental qw(signatures);

use Carp qw( croak );
use CPAN::Meta::Requirements;
use English;
use File::Path qw( make_path remove_tree );
use File::Spec;
use File::Temp qw( tempfile );
use Getopt::Long qw(GetOptionsFromArray);
use HTTP::Tiny;
use IO::Handle;
use JSON::PP;
use List::Util qw(uniq);
use Module::CoreList;
use version;

use Log::Any qw($log);
use Log::Any::Adapter;
use Module::CPANfile;

use LedgerSMB::Installer::Configuration;

my $http = HTTP::Tiny->new( agent => 'LedgerSMB-Installer/0.1' );
my $json = JSON::PP->new;


sub _boot($class, $args, $options) {
    my $dss = $class->_load_dist_support;
    my $config = LedgerSMB::Installer::Configuration->new(
        sys_pkgs => ($EFFECTIVE_USER_ID == 0)
        );

    GetOptionsFromArray(
        $args,
        $config->option_callbacks( $options ),
        );

    # normalize $installpath (at least cpanm needs that)
    # assume $locallib to be inside $installpath
    $config->normalize_paths;

    Log::Any::Adapter->set('Stdout', log_level => $config->loglevel);

    return ($dss, $config);
}

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

sub _get_cpanfile($class, $config) {
    return $config->cpanfile if $config->cpanfile;

    my $response = $http->get(
        sprintf("https://raw.githubusercontent.com/ledgersmb/LedgerSMB/refs/tags/%s/cpanfile",
               $config->version)
        );
    unless ($response->{success}) {
        die $log->fatal("Unable to get 'cpanfile' from GitHub: " + $response->{content});
    }

    my ($fh, $fn) = tempfile();
    print $fh $response->{content};
    $fh->flush;

    my $decl = Module::CPANfile->load( $fn );
    $config->cpanfile( $decl );

    return $decl;
}

sub _get_immediate_prereqs($class, $config) {
    my $decl = $class->_get_cpanfile( $config );
    return $decl->prereqs;
}

sub _compute_immediate_deps($class, $config) {
    my @types     = qw( requires recommends );
    my @phases    = qw( runtime );
    my $decl      = $class->_get_cpanfile( $config );
    my $prereqs   = $decl->prereqs_with( map { $_->identifier } $decl->features ); # all features
    my $effective = CPAN::Meta::Requirements->new;
    for my $phase (@phases) {
        for my $type (@types) {
            $effective->add_requirements( $prereqs->requirements_for( $phase, $type ) );
        }
    }

    my @mods = sort { lc($a) cmp lc($b) } $effective->required_modules;

    $log->debug( "Direct dependency count: " . scalar(@mods) );
    return @mods;
}

sub _compute_all_deps($class, $config) {
    my @deps = $class->_compute_immediate_deps( $config );

    my @last_deps = @deps;
    my %dists;
    my $iteration = 1;
    do {
        my $query = {
            query => { match_all => {} },
            _source => [ qw( release distribution status provides ), 'dependency.*' ],
            filter => {
                and => [
                    { term => { status => 'latest' } },
                    { terms => { provides => [ @last_deps ] } }
                    ]
            }
        };

        my $body = $json->encode( $query );
        my $r = $http->request( 'POST', 'https://fastapi.metacpan.org/v1/release/_search?size=1000',
                                { headers => { 'Content-Type' => 'application/json' },
                                  content => $body });
        my $hits = $json->decode($r->{content})->{hits};

        for my $release ($hits->{hits}->@*) {
            $dists{$release->{_source}->{distribution}} = 1;
        }

        my %provide;
        for my $release ($hits->{hits}->@*) {
            for my $provided ($release->{_source}->{provides}->@*) {
                $provide{$provided} = 1;
            }
        }

        my %rdeps;
        for my $release ($hits->{hits}->@*) {
            for my $dep ($release->{_source}->{dependency}->@*) {
                next unless $dep->{relationship} eq 'requires';
                next unless $dep->{phase} eq 'runtime';
                $rdeps{$dep->{module}} = 1;
            }
        }

        delete $rdeps{perl};
        @last_deps = sort grep {
            my $m = $_;
            my $c = Module::CoreList->is_core($m);

            not ($provide{$m} or $c);
        } keys %rdeps;
        push @deps, @last_deps;

        $log->trace( "Dependency resolution iteration $iteration - "
                     . "remaining to resolve: " . scalar(@last_deps) );
        $iteration++;
    } while (@last_deps);

    @deps = uniq @deps;
    $log->debug( "Dependency tree size: " . scalar(@deps) );
    return uniq @deps;
}

sub _compute_dep_pkgs($class, $dss, $config ) {
    my @mods = $class->_compute_all_deps( $config );
    my ($pkgs, $unmapped) = $dss->pkgs_from_modules( \@mods );

    my $c = scalar(@mods);
    my $p = scalar(keys $pkgs->%*);
    my $u = scalar($unmapped->@*);
    $log->debug( "Resolved $c modules to $p packages; $u unmapped" );
    return ([ sort keys $pkgs->%* ], $unmapped);
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

    local $@ = undef;
    unless (eval "require $oss_class") {
        say "Unable to load $oss_class: $@";
        say "No support for $^O";
        exit 2;
    }

    my $oss = $oss_class->new; # operating system support instance
    $log->debug( "Detecting distribution" );
    return $oss->detect_dss; # detect and return distribution support instance
}

sub compute($class, @args) {
    my ($dss, $config) = $class->_boot(
        \@args,
        [ 'yes|y!', 'target=s', 'local-lib=s', 'log-level=s', 'version=s' ]
        );

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
    do {
        local $@ = undef;
        my $failed = not eval {
            my @remarks = $dss->validate_env(
                $config,
                compute_deps => 1,
                );

            $class->_build_install_tree( $dss, $config->installpath, $config->version );

            $log->info( "Computing O/S packages for declared dependencies" );
            my ($deps, $mods) = $class->_compute_dep_pkgs( $dss, $config );

            my $json = JSON::PP->new->utf8->canonical;
            say $out $json->encode( { identifier => $dss->dependency_packages_identifier,
                                      packages => $deps,
                                      modules => $mods,
                                      name => $dss->name,
                                      version => "1" } );

            return 1;
        };
        $exception = $@;

        if ($config->effective_uninstall_env) {
            $log->warning( "Cleaning up Perl module installation dependencies" );
            $dss->cleanup_env($config);
        }
    };
    die $exception if defined $exception;

    return 0;
}

sub download($class, @args) {
}

sub help($class, @args) {
    say <<~EOT;
    $0 version CLONED

      Commands:
        compute
        download
        install
        help
        system-id
    EOT

    return 0;
}

sub install($class, @args) {
    my $rv = 1;
    my ($dss, $config) = $class->_boot(
        \@args,
        [ 'yes|y!', 'system-packages!', 'prepare-env!', 'target=s',
          'local-lib=s', 'log-level=s', 'verify-sig!', 'version=s' ]
        );

    my $pkg_deps;
    if ($dss->am_system_perl) {
        my $name = $dss->name;
        my $dep_pkg_id = $dss->dependency_packages_identifier;
        if ($config->sys_pkgs) {
            $pkg_deps = $config->retrieve_precomputed_deps($name, $dep_pkg_id);
        }
        if ($pkg_deps) {
            if ($dss->pkg_can_install()) {
                $dss->prepare_builder_environment( $config );
                goto INSTALL_SYS_PKGS;
            }
            else {
                $log->warn( "Unable to install system packages; will resort to installation of CPAN modules" );
                $pkg_deps = undef;
            }
        }
        else {
            $log->warn( "No precomputed dependencies available for $name/$dep_pkg_id" );
            $log->info( "Configuring environment for dependency computation" );
        }
    }

    my $prereqs = $class->_get_immediate_prereqs( $config );
    my $requirements = $prereqs->merged_requirements();


    unless  ($requirements->accepts_module( 'perl', $])) {
        # BAIL: No suitable Perl here...
        #
        # well, we might want to see if Perlbrew is installed with an acceptable version?
        #
        # and if not, we could install Perlbrew here...
        die $log->fatal( "Not running a Perl version compliant with LedgerSMB " . $config->version );
    }


    ########################################################################################
    #
    #  Need to clean up on failure after this point! We're about to change system state!
    #
    ########################################################################################
    $dss->prepare_builder_environment( $config );

    if ($dss->am_system_perl and $dss->pkg_can_install) {  # and $dss->deps_can_map
        goto COMPUTE_SYS_PKGS;
    }

    $log->info( "Checking for availability of DBD::Pg" );
    unless (require DBD::Pg) {
        # don't have DBD::Pg

        # find pg_config
        # find libpq5
        # build against libpq5
        ...;
    }

    $log->info( "Checking for availability of LaTeX::Driver" );
    unless (require LaTeX::Driver) {
        # don't have LaTeX::Driver

        # testing early, because this module only installs
        # when LaTeX is installed...

        ...;
    }

    goto PREPARE_TREE;

  COMPUTE_SYS_PKGS:
    $dss->prepare_pkg_resolver_environment( $config );
    ($pkg_deps) = $class->_compute_dep_pkgs( $dss, $config );

  INSTALL_SYS_PKGS:
    $log->info( "Installing O/S packages: " . join(' ', $pkg_deps->@*) );
    $dss->pkg_install( $pkg_deps );

  PREPARE_TREE:
    $dss->prepare_installer_environment( $config );
    $class->_build_install_tree( $dss, $config->installpath, $config->version );
    $dss->cpanm_install( $config->installpath, $config->locallib );
    $rv = 0;

  CLEANUP:
    $log->warning( "Cleaning up Perl module installation dependencies" );
    $dss->cleanup_env($config);
    return $rv;
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
    elsif ($cmd eq 'help') {
        return $class->help( @args );
    }
    elsif ($cmd eq 'install') {
        return $class->install( @args );
    }
    elsif ($cmd eq 'system-id') {
        return $class->print_id( @args );
    }
    else {
        $class->help();
        exit 1;
    }
}


1;
