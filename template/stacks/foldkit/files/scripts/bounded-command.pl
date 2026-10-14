#!/usr/bin/env perl
# Bound a command and its process group, including descendants holding stdout.
# The group leader stays alive until cleanup, so its group ID cannot be reused.
# The deadline requires a living supervisor; deliberately detached sessions are
# outside the group boundary. Only direct children can be reaped portably.
# No shell interprets argv. Optional --status-file distinguishes command exits
# from signals, deadlines and supervisor failures without changing exit codes.
use strict;
use warnings;
use Errno qw(EINTR);
use POSIX qw(setsid _exit sigprocmask SIG_BLOCK SIG_SETMASK SIGALRM SIGHUP SIGINT SIGTERM);

my $status_file;
if (@ARGV && $ARGV[0] eq '--status-file') {
    shift @ARGV;
    $status_file = shift @ARGV;
}
my $limit = shift @ARGV;
my ($child, $group_ready, $result, $kind) = (undef, 0, 1, 'exit');
my $outcome;
my $blocked = POSIX::SigSet->new(SIGALRM, SIGHUP, SIGINT, SIGTERM);
sub finish {
    my ($status, $reason) = @_;
    # Even a mask failure must reach owned-process cleanup. Ignoring the managed
    # signals is the fallback; no throwing handler can escape this routine.
    my $masked = sigprocmask(SIG_BLOCK, $blocked);
    $SIG{$_} = 'IGNORE' for qw(ALRM HUP INT TERM);
    alarm 0;
    if (!$masked) {
        print STDERR "bounded-command: cannot block cleanup signals: $!\n";
        ($status, $reason) = (125, 'internal');
    }
    if (defined($child) && $child > 0) {
        kill 'KILL', $group_ready ? -$child : $child;
        my $waited;
        do { $waited = waitpid($child, 0); } while $waited < 0 && $! == EINTR;
        if ($waited != $child) {
            print STDERR "bounded-command: cannot reap owned child: $!\n";
            ($status, $reason) = (125, 'internal');
        }
        $child = undef;
    }
    if (defined $status_file) {
        if (!defined($outcome) || !print($outcome "$reason $status\n") || !close($outcome)) {
            print STDERR "bounded-command: cannot write outcome: $!\n";
            exit 125;
        }
    }
    exit $status;
}
if (defined($status_file) && !open($outcome, '>', $status_file)) {
    print STDERR "bounded-command: cannot open outcome: $!\n";
    finish(125, 'internal');
}
if (!defined($limit) || $limit !~ /^[1-9][0-9]*$/ || !@ARGV) {
    print STDERR "usage: bounded-command.pl [--status-file PATH] SECONDS COMMAND [ARG ...]\n";
    finish(125, 'internal');
}
for my $entry ([ALRM => 142, 'timeout'], [HUP => 129, 'signal'],
               [INT => 130, 'signal'], [TERM => 143, 'signal']) {
    my ($name, $status, $reason) = @$entry;
    $SIG{$name} = sub { finish($status, $reason); };
}

my $ok = eval {
    pipe(my $ready, my $report) or die "pipe: $!\n";
    pipe(my $release, my $control) or die "pipe: $!\n";
    alarm $limit;
    # Do not deliver a pending signal between fork and storing the owned PID.
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
        close $outcome if defined $outcome;
        close $ready;
        close $control;
        defined(setsid()) && getpgrp() == $$ or _exit(125);
        # One short write is unbuffered; nothing executes before the parent ACK.
        syswrite($report, "ready\n") == 6 or _exit(125);
        my $ack;
        sysread($release, $ack, 1) == 1 && $ack eq 'x' or _exit(125);
        my $command = fork();
        if (!defined $command) {
            syswrite($report, "error fork\n");
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
        my $status = $?;
        # Only the leader ignores PIPE, after the command fork. A vanished
        # supervisor must not prevent the EOF/group cleanup below.
        $SIG{PIPE} = 'IGNORE';
        syswrite($report, $waited == $command ? "status $status\n" : "error wait\n");
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
    $kind = ($status & 127) ? 'signal' : 'exit';
    $result = ($status & 127) ? 128 + ($status & 127) : $status >> 8;
    1;
};
my $error = $@;
if (!$ok) {
    print STDERR $error;
    finish(125, 'internal');
}
finish($result, $kind);
