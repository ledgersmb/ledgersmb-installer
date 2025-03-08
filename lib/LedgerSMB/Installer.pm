package LedgerSMB::Installer;

use v5.34;
use experimental qw(signatures try);

use Cwd;
use Getopt::Long qw(GetOptionsFromArray);

use Log::Any qw($log);
use Log::Any::Adapter;

use LedgerSMB::Installer::Configuration;

sub download($class, @args) {


}

sub install($class, @args) {
    my $version;
    my $verify = 1;
    my $loglevel = 'info';
    my $locallib = 'local';
    my $installpath = 'ledgersmb';
    my $force_compute_deps = 0;
    GetOptionsFromArray(
        \@args,
        'force-compute-deps' => \$force_compute_deps,
        'log-level=s'        => \$loglevel,
        'verify!'            => \$verify,
        'version=s'          => \$version,
        );

    Log::Any::Adapter->set('Stdout', log_level => $loglevel);

    my $config = LedgerSMB::Installer::Configuration->new(
        version => $version,
        );

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
        unless $force_compute_deps;
    unless ($deps) {
        $log->warn( "No precomputed dependencies available for this distro/version" );
        $log->info( "Configuring environment for dependency computation" );
    }

    my @remarks = $dss->validate_env(
        compute_deps => defined($deps),
        install_deps => 1,
        );

    # Generate script
    # 1. create installation directory
    # 2. download tarball
    # 3. unpack tarball
    # 4. delete tarball
    # in case of missing precomputed deps:
    #   5. compute dependencies (distro packages)
    # 6. install (pre)computed dependencies (distro packages)
    # 7. install CPAN dependencies (using cpanm & local::lib)
    # 8. generate startup script (set local::lib environment)

    my @cmds;
    $dss->mkdir( \@cmds, $installpath );
    $dss->download( \@cmds, $version, $installpath );
    my $archive = "$installpath/ledgersmb-$version.tar.gz";
    $dss->verify_gpg( \@cmds, $archive )
        if $verify;
    $dss->untar( \@cmds, $archive, $installpath, strip_components => 1 );
    $dss->rm( \@cmds, $archive );

    my $computed_deps;
    if (not $deps
        and $dss->{_have_pkgs}) {
        $computed_deps = "$installpath/tmp/computed-deps";
        $dss->compute_dep_packages( \@cmds, $installpath, $computed_deps );
    }

    $dss->pkg_install( \@cmds, $deps, $computed_deps );
    $dss->cpanm_install( \@cmds, $installpath, $locallib );
    $dss->generate_startup( \@cmds, $installpath, $locallib );

    say "SCRIPT:\n\n" . join("\n", @cmds);
    open my $fh, '>', 'lsmb-inst';
    say $fh join("\n", @cmds);
    close $fh;

    return 0;
}

sub run($class, @args) {

    return $class->install( @args );
}


1;
