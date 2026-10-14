#!/usr/bin/env perl
# Bound a command and its process group, including descendants holding stdout.
# The group leader stays alive until cleanup, so its group ID cannot be reused.
# Deliberately detached sessions are outside this boundary; only direct children
# can be reaped portably. No shell interprets the command argument vector.
use strict;
use warnings;
use Errno qw(EINTR);
use POSIX qw(setsid _exit sigprocmask SIG_BLOCK SIG_SETMASK SIGALRM SIGHUP SIGINT SIGTERM);

my $limit = shift @ARGV;
die "usage: bounded-command.pl SECONDS COMMAND [ARG ...]\n"
    unless defined($limit) && $limit =~ /^[1-9][0-9]*$/ && @ARGV;
pipe(my $ready, my $report) or die "pipe: $!\n";
pipe(my $release, my $control) or die "pipe: $!\n";
my ($child, $group_ready, $result) = (undef, 0, 1);
my $interrupted;
for my $entry ([ALRM => 142], [HUP => 129], [INT => 130], [TERM => 143]) {
    my ($name, $status) = @$entry;
    $SIG{$name} = sub { $interrupted = $status; die "bounded-command interrupted\n"; };
}

my $ok = eval {
    alarm $limit;
    # Do not deliver a pending signal between fork and storing the owned PID.
    my $blocked = POSIX::SigSet->new(SIGALRM, SIGHUP, SIGINT, SIGTERM);
    my $previous = POSIX::SigSet->new();
    sigprocmask(SIG_BLOCK, $blocked, $previous) or die "block signals: $!\n";
    $child = fork();
    if (!defined $child) {
        sigprocmask(SIG_SETMASK, $previous);
        die "fork: $!\n";
    }
    if ($child == 0) {
        alarm 0;
        $SIG{$_} = 'DEFAULT' for qw(ALRM HUP INT TERM);
        sigprocmask(SIG_SETMASK, $previous) or _exit(125);
        close $ready;
        close $control;
        defined(setsid()) && getpgrp() == $$ or _exit(125);
        # One short write is unbuffered; nothing executes before the parent ACK.
        syswrite($report, "ready\n") == 6 or _exit(125);
        my $ack;
        sysread($release, $ack, 1) == 1 && $ack eq 'x' or _exit(125);
        my $command = fork();
        if (!defined $command) {
            syswrite($report, "error\n");
            _exit(125);
        }
        if ($command == 0) {
            close $report;
            close $release;
            exec { $ARGV[0] } @ARGV or do {
                print STDERR "cannot run $ARGV[0]: $!\n";
                _exit(127);
            };
        }
        my $waited;
        do { $waited = waitpid($command, 0); } while $waited < 0 && $! == EINTR;
        my $status = $waited == $command ? $? : 125 << 8;
        syswrite($report, "status $status\n");
        # Retain the session/group leader until the supervisor KILLs the group.
        # EOF also means the supervisor disappeared, so clean up our own group.
        sysread($release, $ack, 1);
        kill 'KILL', -$$;
        _exit(125);
    }
    sigprocmask(SIG_SETMASK, $previous) or die "restore signals: $!\n";
    close $report;
    close $release;
    my $line = <$ready>;
    die "command group setup failed\n" unless defined($line) && $line eq "ready\n";
    $group_ready = 1;
    syswrite($control, 'x') == 1 or die "command group acknowledgement failed\n";
    $line = <$ready>;
    die "command supervisor failed\n" unless defined($line) && $line =~ /^status ([0-9]+)\n$/;
    my $status = $1;
    $result = ($status & 127) ? 128 + ($status & 127) : $status >> 8;
    1;
};
my $error = $@;
# Cleanup cannot itself be interrupted. Before ACK the child has no command or
# descendants; afterward the still-owned session is safe to address as a group.
$SIG{$_} = 'IGNORE' for qw(ALRM HUP INT TERM);
alarm 0;
if (defined($child) && $child > 0) {
    kill 'KILL', $group_ready ? -$child : $child;
    my $waited;
    do { $waited = waitpid($child, 0); } while $waited < 0 && $! == EINTR;
}
if (defined $interrupted) {
    exit $interrupted;
}
if (!$ok) {
    print STDERR $error;
    exit 125;
}
exit $result;
