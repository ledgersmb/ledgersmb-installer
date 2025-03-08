package LedgerSMB::Installer::OS::linux::debian;

use v5.34;
use experimental qw( try signatures );

use parent qw( LedgerSMB::Installer::OS::linux );

use HTTP::Tiny;
use JSON::PP;
use Log::Any qw($log);

sub new($class, %args) {
    return bless {
        _config => $args{config},
        _distro => $args{distro},
        _have_deps => 0,
        _have_pkgs => 1,
    }, $class;
}

sub retrieve_precomputed_deps($self) {
    my $http = HTTP::Tiny->new;
    my $url  = $self->{_config}->dependency_url(
        $self->{_distro}->{ID}, $self->{_distro}->{VERSION_CODENAME}
        );

    $log->info( "Retrieving dependency listing from $url" );
    my $r = $http->get( $url );
    if ($r->{success}) {
        $self->{_have_deps} = 1;
        return JSON::PP->new->utf8->decode( $r->{content} );
    }
    elsif ($r->{status} == 599) {
        die $log->fatal(
            'Error trying to retrieve precomputed dependencies: ' . $r->{content}
            );
    }
    return;
}

sub compute_dep_packages( $self, $cmds, $installpath, $outputpath ) {
    unshift $cmds->@*, (
        <<~SCRIPT,
        function lsmb-dep-pkgs {
        ( cd '$installpath' ;
          $self->{cmd}->{'apt-file'} update
          for mod in \$( $self->{cmd}->{'cpanfile-dump'} --with-all-features --recommends --no-configure --no-build --no-test )
          do
            $self->{cmd}->{'dh-make-perl'} locate "\$mod" 2>/dev/null | grep -vE 'dh-make-perl|not found|is in Perl' || true
          done
        ) | $self->{cmd}->{cut} -d' ' -f4 | $self->{cmd}->{sort} | $self->{cmd}->{uniq}
        }

        SCRIPT
        );
    push $cmds->@*, "lsmb-dep-pkgs >'$outputpath'";
}

sub pkg_install($self, $cmds, $pkgs, $file) {
    $pkgs //= [];
    push $cmds->@*, (
        "DEBIAN_FRONTEND=noninteractive $self->{cmd}->{'apt-get'} update -q -y",
        "DEBIAN_FRONTEND=noninteractive $self->{cmd}->{'apt-get'} install -q -y " . join(' ', $pkgs->@*) . ($file ? "\$($self->{cmd}->{cat} $file)" : '')
        );
}

sub validate_env($self, %args) {
    $self->SUPER::validate_env(
        %args,
        );
    $self->have_cmd( 'apt-get', 1 ); # required to install dependencies
    $self->have_cmd( 'apt-file', not $self->{_have_deps} ); # required for computation of dependencies
    $self->have_cmd( 'dh-make-perl', not $self->{_have_deps} );
    $self->have_cmd( 'cpanfile-dump', not $self->{_have_deps} );
    $self->have_cmd( 'cat' );
    $self->have_cmd( 'cut' );
    $self->have_cmd( 'sort' );
    $self->have_cmd( 'uniq' );
}

1;
