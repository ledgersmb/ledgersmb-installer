package LedgerSMB::Installer::OS::linux;

use v5.34;
use experimental qw(signatures try);
use parent qw(LedgerSMB::Installer::OS::unix);

use Carp qw(croak);

use Log::Any qw($log);

sub new($class, %args) {
    return bless {
    }, $class;
}

sub detect_dss($self) {
    my $dss_class;

    if (-r '/etc/os-release') {
        if (open my $fh, '<', '/etc/os-release') {
            my %params;
            while (my $line = <$fh>) {
                next if $line =~ m/^.*#/;
                next if $line =~ m/^\s*$/;

                my ($var, $val) = split( /="?/, $line, 2);
                $val =~ s/"$//;
                chomp $val;
                $params{$var} = $val;
            }

            $self->{distro} = { %params{ qw(ID ID_LIKE VERSION_ID VERSION_CODENAME)} };
            close($fh)
                or warn $log->warn( "Unable to close /etc/os-release" );

            my $dist_id = $self->{distro}->{ID};
            my $dist_like_id;
            $dss_class = __PACKAGE__ . '::' . $dist_id;
            if (not eval "require $dss_class") {
                my $alt_dss_class;
                if ($self->{distro}->{ID_LIKE}) { # ID_LIKE is optional
                    my @like_dists = split( / +/, $self->{distro}->{ID_LIKE} );
                    my @attempts;
                    for my $like_dist (@like_dists) {
                        $dist_like_id = $like_dist;
                        my $alt = __PACKAGE__ . "::$like_dist";
                        if (eval "require $alt") {
                            $alt_dss_class = $alt;
                            last;
                        }
                        push @attempts, $alt;
                    }
                    if (not $alt_dss_class) {
                        my $distros = join(', ', $self->{distro}->{ID}, @like_dists);
                        die $log->error( 'Unable to load support for any of these linux '
                                         . "distributions: $distros" );
                    }
                }
                else {
                    die 'Unable to load support for linux distribution: '
                        . "$self->{distro}->{ID}\n";
                }
                $dss_class = $alt_dss_class;
            }
            if ($dist_like_id) {
                $log->info( "Dectected distribution: $dist_like_id (from: $dist_id)" );
            }
            else {
                $log->info( "Detected distribution: $dist_id" );
            }
        }
        else {
            $log->warn( "Failed to open /etc/os-release: $!" );
            die $log->error( "Failed to identify distribution using /etc/os-release" );
        }
    }


    return $dss_class->new(
        distro => $self->{distro},
        );
}

sub generate_startup($self, $config) {
    $log->warning( "Generation of startup scripts not implemented" );
}

1;
