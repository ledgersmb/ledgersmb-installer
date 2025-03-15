package LedgerSMB::Installer::Configuration;

use v5.36;
use experimental qw( try signatures );

use Cwd qw( getcwd );
use File::Spec;
use Symbol;


use HTTP::Tiny;
use Log::Any qw($log);

sub new( $class, %args ) {
    return bless {
        # initialization options
        _assume_yes  => $args{assume_yes} // 0,
        _installpath => $args{installpath} // 'ledgersmb',
        _locallib    => $args{locallib} // 'local',
        _loglevel    => $args{loglevel} // 'info',
        _prep_env    => $args{prepare_env},
        _sys_pkgs    => $args{pkgs},
        _verify_sig  => $args{verify_sig} // 1,
        _version     => $args{version},
        _uninstall_env  => $args{uninstall_env},

        # internal state
        _deps  => undef,
        _cleanup_pkgs => [],
    }, $class;
}

sub dependency_url($self, $distro, $id) {
    return "https://download.ledgersmb.org/f/dependencies/$distro/$id.json" ;
}

sub have_deps($self) {
    return (defined $self->{_deps}
            and defined $self->{_deps}->{packages}
            and $self->{_deps}->{packages}->@*);
}

sub retrieve_precomputed_deps($self, $name, $id) {
    return unless $name and $id;

    my $http = HTTP::Tiny->new;
    my $arch = `dpkg --print-architecture`;
    chomp($arch);
    my $url  = $self->dependency_url($name, $id);

    $log->info( "Retrieving dependency listing from $url" );
    my $r = $http->get( $url );
    if ($r->{success}) {
        $self->{_deps} = JSON::PP->new->utf8->decode( $r->{content} );
        return $self->{_deps}->{packages};
    }
    elsif ($r->{status} == 599) {
        die $log->fatal(
            'Error trying to retrieve precomputed dependencies: ' . $r->{content}
            );
    }
    return;
}

sub mark_pkgs_for_cleanup($self, $pkgs) {
    push $self->{_cleanup_pkgs}->@*, $pkgs->@*;
}

sub pkgs_for_cleanup($self) {
    return $self->{_cleanup_pkgs}->@*;
}

sub normalize_paths($self) {
    my $installpath = $self->installpath;
    if (not File::Spec->file_name_is_absolute( $installpath )) {
        my @dirs = File::Spec->splitdir( $installpath );
        if (@dirs) {
            if ($dirs[0] ne File::Spec->curdir) {
                $self->installpath( File::Spec->catdir( getcwd(), $installpath ) );
            }
        }
    }
    my $locallib = $self->locallib;
    if (not File::Spec->file_name_is_absolute( $locallib )) {
        my @dirs = File::Spec->splitdir( $locallib );
        if (@dirs == 1) {
            $self->locallib( File::Spec->catdir( $installpath, $locallib ) );
        }
        else {
            $self->locallib( File::Spec->catdir( getcwd(), $locallib ) );
        }
    }
}

sub effective_prepare_env( $self ) {
    if (defined $self->prepare_env) {
        return $self->prepare_env;
    }

    return 1 if $self->assume_yes;

    # ask and set 'prepare_env' (so uninstall_env can use it) ...
}

sub effective_uninstall_env( $self ) {
    if (defined $self->uninstall_env) {
        return $self->uninstall_env;
    }

    return $self->prepare_env;
}

for my $acc (qw( assume_yes installpath locallib loglevel prepare_env sys_pkgs
                 verify_sig uninstall_env version )) {
    my $ref = qualify_to_ref $acc;
    *{$ref} = sub($self, $arg = undef) {
        $self->{"_$acc"} = $arg
            if defined $arg;
        return $self->{"_$acc"};
    };
}

1;
