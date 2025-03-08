package LedgerSMB::Installer::OS::unix;

use v5.34;
use experimental qw(try signatures);

use Log::Any qw($log);

sub have_cmd($self, $cmd, $fatal = 1) {
    my $executable = `which "$cmd" 2>/dev/null`;
    chomp $executable;
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

sub validate_env($self, @args) {
    $self->have_cmd('cpanm', 0);
    $self->have_cmd('wget',  0);
    $self->have_cmd('curl',  0);
    $self->have_cmd('cc',    0); # might be used during dist-installation
    $self->have_cmd('gcc',   0); # might be used during dist-installation
    $self->have_cmd('cpp',   0); # might be used during dist-installation
    $self->have_cmd('c++',   0); # might be used during dist-installation
    $self->have_cmd('gzip');     # fatal, used by 'tar'
    $self->have_cmd('mkdir');    # fatal
    $self->have_cmd('chmod');    # fatal
    $self->have_cmd('rm');       # fatal
    $self->have_cmd('tar');      # fatal
    $self->have_cmd('make');     # fatal
    $self->have_cmd('gpg');      # fatal
}

sub cpanm_install($self, $cmds, $installpath, $locallib) {
    unless ($self->{cmd}->{cpanm}) {
        $self->mkdir( $cmds, "$installpath/tmp" );

        if ($self->{cmd}->{curl}) {
            push $cmds->@*, (
                "$self->{cmd}->{curl} -sL https://cpanmin.us/ --output-dir $installpath/tmp -o cpanm",
                );
        }
        elsif ($self->{cmd}->{wget}) {
            push $cmds->@*, (
                "$self->{cmd}->{wget} --quiet -O $installpath/tmp/cpanm https://cpanmin.us/",
                );
        }
        push $cmds->@*,
            "$self->{cmd}->{chmod} +x '$installpath/tmp/cpanm'";

        $self->{cmd}->{cpanm} = "$installpath/tmp/cpanm";
    }
    push $cmds->@*, "$self->{cmd}->{cpanm} --notest --with-all-features --local-lib '$locallib' --installdeps '$installpath'";
}

sub download($self, $cmds, $version, $installpath) {
    my $fn = "ledgersmb-$version.tar.gz";
    my $url = "https://download.ledgersmb.org/f/Releases/$version";

    if ($self->{cmd}->{curl}) {
        push $cmds->@*, (
            "$self->{cmd}->{curl} -sL $url/$fn --output-dir $installpath --output $fn",
            "$self->{cmd}->{curl} -sL $url/$fn.asc --output-dir $installpath --output $fn.asc"
            );
    }
    elsif ($self->{cmd}->{wget}) {
        push $cmds->@*, (
            "$self->{cmd}->{wget} --quiet -O $installpath/$fn $url/$fn",
            "$self->{cmd}->{wget} --quiet -O $installpath/$fn.asc $url/$fn.asc"
            );
    }
}

sub mkdir($self, $cmds, $path) {
    push $cmds->@*, "$self->{cmd}->{mkdir} -p '$path'";
}

sub pkg_install($self, $cmds, $pkgs) {
    croak $log->error( 'Generic linux support does not include package installers' );
}

sub rm($self, $cmds, $file) {
    push $cmds->@*, "$self->{cmd}->{rm} '$file'";
}

sub untar($self, $cmds, $tar, $target, %options) {
    my $strip = $options{strip_components} ? "--strip-components $options{strip_components}" : '';
    push $cmds->@*, "$self->{cmd}->{tar} xzf '$tar' -C '$target' $strip";
}

sub verify_gpg($self, $cmds, $file) {
    push $cmds->@*, (
        "<import-gpg-key>",
        "$self->{cmd}->{gpg} --verify $file.asc $file"
        );
}

1;
