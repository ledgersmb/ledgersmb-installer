package LedgerSMB::Installer::Configuration;

use v5.36;
use experimental qw( try signatures );

use Cwd qw( getcwd );
use File::Spec;
use Symbol;

sub new( $class, %args ) {
    return bless {
        _assume_yes  => $args{assume_yes} // 0,
        _installpath => $args{installpath} // 'ledgersmb',
        _locallib    => $args{locallib} // 'local',
        _loglevel    => $args{loglevel} // 'info',
        _prep_env    => $args{prepare_env},
        _sys_pkgs    => $args{pkgs},
        _verify_sig  => $args{verify_sig} // 1,
        _version     => $args{version}
        _uninstall_env  => $args{uninstall_env},
    }, $class;
}

sub dependency_url($self, $distro, $id) {
    return "https://download.ledgersmb.org/f/dependencies/$distro/$id.json" ;
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
