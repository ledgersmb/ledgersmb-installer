package LedgerSMB::Installer::OS;

use v5.34;
use experimental qw(try signatures);

use Cwd qw( getcwd );
use File::Basename qw( fileparse );
use File::Spec;

use Log::Any qw($log);

sub have_cmd($self, $cmd, $fatal = 1, $extra_path = []) {
    if ($self->{cmd} and $self->{cmd}->{$cmd}) {
        $log->debug( "Found cached command $self->{cmd}->{$cmd}" );
        return $self->{cmd}->{$cmd};
    }

    my $executable = '';
    if (File::Spec->file_name_is_absolute( $cmd )) {
        $executable = $cmd if -x $cmd;
    }
    else {
        my (undef, $dirs) = File::Spec->splitpath( $cmd );
        if ($dirs) {
            $cmd = File::Spec->catfile( getcwd(), $cmd );
            $executable = $cmd if -x $cmd;
        }
        else {
            for my $path (File::Spec->path, $extra_path->@*) {
                my $expanded = File::Spec->catfile( $path, $cmd );
                next if not -x $expanded;

                $executable = $expanded;
                last;
            }
        }
    }
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

sub pg_config_extra_paths($self) {
    return ();
}

sub pkg_from_module($self, $mod) {
    die 'Operating system and distribution support needs to override the "pkg_from_module" method';
}

sub pkg_can_install($self) {
    return 0; # there's no such thing as generic installer support across operating systems
}

sub pkg_install($self) {
    die 'Operating system and distribution support needs to override the "pkg_install" method';
}

sub pkg_uninstall($self) {
    die 'Operating system and distribution support needs to override the "pkg_uninstall" method';
}

sub name($self) {
    die 'Operating system and distribution support needs to override the "name" method';
}

sub cleanup_env($self, $config) {
}

sub prepare_env($self, $config) {
}

sub validate_env($self, $config, @args) {
}

1;
