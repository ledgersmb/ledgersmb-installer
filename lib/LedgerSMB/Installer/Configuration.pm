package LedgerSMB::Installer::Configuration;

use v5.36;
use experimental qw( try signatures );

use Cwd qw( getcwd );
use File::Spec;
use Symbol;

sub new( $class, %args ) {
    return bless {
        _installpath => $args{installpath},
        _locallib => $args{locallib},
        _loglevel => $args{loglevel},
        _version => $args{version}
    }, $class;
}

sub dependency_url($self, $distro, $distro_version = '', $arch = '') {
    $distro_version .= '-' if $distro_version;
    $arch .= '-' if $arch;
    return "https://download.ledgersmb.org/f/dependencies/$distro/$distro_version$arch$self->{_version}.json" ;
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


for my $acc (qw( installpath locallib loglevel verify_sig version )) {
    my $ref = qualify_to_ref $acc;
    *{$ref} = sub($self, $arg = undef) {
        $self->{"_$acc"} = $arg
            if defined $arg;
        return $self->{"_$acc"};
    };
}

1;
