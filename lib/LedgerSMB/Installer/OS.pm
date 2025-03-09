package LedgerSMB::Installer::OS;

use v5.34;
use experimental qw(try signatures);

use Cwd qw( getcwd );
use File::Basename qw( fileparse );
use File::Spec;

use Log::Any qw($log);

sub have_cmd($self, $cmd, $fatal = 1, $extra_path = []) {
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

sub validate_env($self, @args) {
}

1;
