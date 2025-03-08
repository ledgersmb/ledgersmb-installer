package LedgerSMB::Installer::OS::unix;

use v5.34;
use experimental qw(try signatures);

use Carp qw( croak );
use File::Path qw( make_path );
use HTTP::Tiny;
use Log::Any qw($log);

sub have_cmd($self, $cmd, $fatal = 1) {
    my $executable = `which "$cmd" 2>/dev/null`;
    chomp $executable;
    if ($executable) {
        $self->{cmd} //= {};
        $self->{cmd}->{$cmd} = $executable;
        $log->info( "Command $cmd found as $executable" );
    }
    elsif (not $fatal) {
        $log->info( "Command $cmd not found" );
    }
    else {
        die "Missing '$cmd'";
    }
    return $executable;
}

sub validate_env($self, @args) {
    $self->have_cmd('cpanm', 0);
    $self->have_cmd('wget',  0);
    $self->have_cmd('curl',  0);
    $self->have_cmd('cc',    0); # might be used during dist-installation
    $self->have_cmd('gcc',   0); # might be used during dist-installation
    $self->have_cmd('cpp',   0); # might be used during dist-installation
    $self->have_cmd('c++',   0); # might be used during dist-installation
    $self->have_cmd('gzip');     # fatal, used by 'tar'
    $self->have_cmd('mkdir');    # fatal
    $self->have_cmd('chmod');    # fatal
    $self->have_cmd('rm');       # fatal
    $self->have_cmd('tar');      # fatal
    $self->have_cmd('make');     # fatal
    $self->have_cmd('gpg');      # fatal
}

sub cpanm_install($self, $installpath, $locallib) {
    unless ($self->{cmd}->{cpanm}) {
        make_path( File::Spec->catfile( $installpath, 'tmp' ) );

        my $http = HTTP::Tiny->new;
        my $r    = $http->get( 'https://cpanmin.us/' );
        if ($r->{status} == 599) {
            croak $log->fatal( "Unable to request https://cpanmin.us/: " . $r->{content} );
        }
        elsif (not $r->{success}) {
            croak $log->fatal( "Unable to request https://cpanmin.us/: $r->{status} - $r->{reason}" );
        }
        else {
            my $cpanm = File::Spec->catfile( $installpath, 'tmp', 'cpanm' );
            open( my $fh, '>', $cpanm )
                or croak $log->fatal( "Unable to open output file tmp/cpanm" );
            binmode $fh, ':raw';
            print $fh $r->{content};
            close( $fh ) or warn $log->warning( "Failure closing file tmp/cpanm" );
            chmod( 0755, $cpanm ) or warn $log->warning( "Failure making tmp/cpanm executable" );
            $self->{cmd}->{cpanm} = $cpanm;
        }

    }

    my @cmd = (
        $self->{cmd}->{cpanm},
        '--notest',
        '--with-all-features',
        '--local-lib', $locallib,
        '--installdeps', "$installpath"
        );

    $log->debug( "system(): " . join(' ', map { "'$_'" } @cmd ) );
    system(@cmd) == 0
        or croak $log->fatal( "Failure running cpanm - exit code: $?" );
}

sub pkg_from_module($self, $mod) {
    croak $log->fatal( 'Generic Unix support does not include package installers' );
}

sub pkg_install($self, $pkgs) {
    croak $log->error( 'Generic linux support does not include package installers' );
}

sub untar($self, $tar, $target, %options) {
    my @cmd = ($self->{cmd}->{tar}, 'xzf', $tar, '-C', $target);
    push @cmd, ('--strip-components', $options{strip_components})
        if $options{strip_components};
    $log->debug( 'system(): ' . join(' ', map { "'$_'" } @cmd ) );
    system(@cmd) == 0
        or croak $log->fatal( "Failure executing tar: $!" );
}

sub verify_gpg($self, $cmds, $file) {
    push $cmds->@*, (
        "<import-gpg-key>",
        "$self->{cmd}->{gpg} --verify $file.asc $file"
        );
}

1;
