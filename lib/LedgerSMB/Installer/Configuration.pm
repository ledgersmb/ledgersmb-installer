package LedgerSMB::Installer::Configuration;

use v5.36;
use experimental qw( try signatures );

use Symbol;

sub new( $class, %args ) {
    return bless {
        _version => $args{version}
    }, $class;
}

sub dependency_url($self, $distro, $distro_version = '', $arch = '') {
    $distro_version .= '-' if $distro_version;
    $arch .= '-' if $arch;
    return "https://download.ledgersmb.org/f/dependencies/$distro/$distro_version$arch$self->{_version}.json" ;
}

for my $acc (qw( loglevel version )) {
    my $ref = qualify_to_ref $acc;
    *{$ref} = sub($self, $arg = undef) {
        $self->{"_$acc"} = $arg
            if defined $arg;
        return $self->{"_$acc"};
    };
}

1;
