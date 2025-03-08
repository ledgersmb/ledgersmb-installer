package LedgerSMB::Installer::PkgMan::APT;

use v5.36;
use experimental qw( try signatures );

use Log::Any qw($log);

sub new($class, %args) {
    return bless {
    }, $class;
}



1;

