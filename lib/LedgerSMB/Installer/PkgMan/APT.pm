package LedgerSMB::Installer::PkgMan::APT;

use v5.20;
use experimental qw(signatures);

use Log::Any qw($log);

sub new($class, %args) {
    return bless {
    }, $class;
}



1;

