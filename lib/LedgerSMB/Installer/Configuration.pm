package LedgerSMB::Installer::Configuration;

use v5.36;
use experimental qw( try signatures );

sub new( $class, %args ) {
    return bless {
        _version => $args{version}
    }, $class;
}

sub dependency_url($self, $distro, $distro_version = '') {
    $distro_version .= '-' if $distro_version;
    return "https://download.ledgersmb.org/f/dependencies/$distro/$distro_version$self->{_version}.json" ;
}

1;
