#!/usr/bin/env perl
###
# Daemonized verion of traceping_worker.pl
#
# Should probably be daemonized via Daemon::Control or something a long those lines.
###
use warnings;
use strict;
use POE qw(Wheel::Run Filter::Reference);

use DBI;
use DBD::SQLite;
use Data::Dumper;

use Smokeping;

# CONFIG VARS, CHANGE THESE TO YOUR SETUP.
#
my $config_file = '/etc/smokeping/config';

my $dsn = "dbi:SQLite:dbname=/tmp/test.sqlite";
my $db_username = '';
my $db_password = '';

my $log_level = 1;

my $number_of_workers = 3; # change this to change number of workers

my @target_queue = _load_targets();

POE::Session->create(
  inline_states => {
    _start      => \&start_tasks,
    next_task   => \&start_tasks,
    task_result => \&handle_task_result,
    task_done   => \&handle_task_done,
    task_debug  => \&handle_task_debug,
    sig_child   => \&sig_child,
  }
);

sub start_tasks {
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  while (keys(%{$heap->{task}}) < $number_of_workers ) {
    my $next_task = shift @target_queue;
    push @target_queue, $next_task; # drop on to the end of the array

    _do_log( 1, "Starting traceroute for: " . $next_task->{'target'} );
    my $task = POE::Wheel::Run->new(
      Program      => sub { do_traceroute($next_task) },
      StdoutFilter => POE::Filter::Reference->new(),
      StdoutEvent  => "task_result",
      StderrEvent  => "task_debug",
      CloseEvent   => "task_done",
    );
    $heap->{task}->{$task->ID} = $task;
    $kernel->sig_child($task->PID, "sig_child");
  }
}

sub do_traceroute {
  my $target_hr   = shift;
  my $filter = POE::Filter::Reference->new();

  my $host = $target_hr->{'host'};
  my $target = $target_hr->{'target'};
	
  # run traceroute and generate result
  my %result = (
    target   => $target,
    traceroute_out => _get_traceroute_out($host),
    host => $host,
    status => "seems ok to me",
  );

  # Drop the result into a filter that is passed back the POE kernel for processing
  my $output = $filter->put([\%result]);
  print @$output;
}

sub handle_task_result {
  my $result = $_[ARG0];
  log_traceroute( $result->{'target'}, $result->{traceroute_out} );
}

sub handle_task_debug {
  my $result = $_[ARG0];
  print STDERR "Child STDERR: $result\n";
}

sub handle_task_done {
  my ($kernel, $heap, $task_id) = @_[KERNEL, HEAP, ARG0];
  delete $heap->{task}->{$task_id};
  $kernel->yield("next_task");
}

# Detect the CHLD signal as each of our children exits.
sub sig_child {
  my ($heap, $sig, $pid, $exit_val) = @_[HEAP, ARG0, ARG1, ARG2];
  my $details = delete $heap->{$pid};

  # warn "$$: Child $pid exited";
}

# Run until there are no more tasks.
$poe_kernel->run();
exit 0;

####
# Smokeping-specific code
####

# _load_targets
#
# Should load in the targets from smokeping and return:
# (
# {
#	'target'	=> 'Foo.Bar',
#	'host' 		=> 'foo.example.com',
# }
# )
sub _load_targets {
	my @targets;

	Smokeping::load_cfg($config_file, 1);
	# get each server's info.
	foreach my $group ( keys %{ $Smokeping::cfg->{'Targets'} } ) {
		unless ( ref $Smokeping::cfg->{'Targets'}->{$group} ) {
			# Unless the entry in the smokeping hash is a reference to another datastructure
			next;
		}
		my $group_hr = $Smokeping::cfg->{'Targets'}->{$group};

		foreach my $server ( keys %{ $group_hr } ) {
			unless ( ref $group_hr->{$server} && ref $group_hr->{$server} eq 'HASH' ) {
				# Unless the entry in the smokeping hash is a reference to another datastructure
				next;
			}

			# set target to Group.Name, like in the UI
			my $target = "${group}.${server}";

			if ( !exists $group_hr->{$server}->{'host'} ) {
				# this is actually just another level deeper of config
				# This is for entries that are +++ headed, if we need another level, we'll make this recursive
				foreach my $third_level ( keys %{ $group_hr->{$server} } ) {
					next if ref $group_hr->{$server}->{$third_level} ne 'HASH';
					next if !exists $group_hr->{$server}->{$third_level}->{'host'};
					my $host = $group_hr->{$server}->{$third_level}->{'host'};
					push @targets, { 'target' => "${target}.${third_level}", 'host' => $host };
				} 
			}
			else {
				my $host = $group_hr->{$server}->{host};
				push @targets, { 'target' => $target, 'host' => $host };
			}


		}
	}
	return @targets;
}

# _do_log ( $level, $msg )
#
# Log a message (at this point, this means print to STDERR)
#
# Really just a stub for rounding out later
sub _do_log {
	my ( $level, $msg ) = @_;
	if ( $level >= $log_level ) {
		print STDERR "${msg}\n";
	}
}

###
# Traceroute functoins
###

# get a traceroute's output or die a terrible terrible death (or something)
sub _get_traceroute_out {
	my ( $host ) = @_;
	my @output;

	my $last_index_with_data = 0;
	my $index = 0;

	open my $tracert_out, "-|", "traceroute", $host;
	while ( my $line = readline $tracert_out ) {
		chomp $line;

		if ( $line =~ /\s*\d+\s+([a-z0-9\*].+)$/i ) {
			# keep track of when we just get * * * responses so that we can strip them out
			$last_index_with_data = $index if $1 ne '* * *';
		}

		push @output, $line;
		$index++;
	}
	close $tracert_out;

	return join("\n", @output[0 .. $last_index_with_data]);
}

###
# SQL-management functions
###

my %index_cache;

sub log_traceroute {
	my ( $target, $output ) = @_;

	my $dbh = DBI->connect($dsn, $db_username, $db_password);
	my $index = _get_index( $dbh, $target );

	my $sth = $dbh->prepare( 'UPDATE host SET tracert=? WHERE host_id=?');
	$sth->execute($output, $index);	
}

# get the index for a target
# or give it an entry to update
# 
# ALWAYS cache the result so that we can avoid a bunch of extra queries
sub _get_index {
	my ( $dbh, $target ) = @_;

	if ( !exists $index_cache{$target} ) {
	    my $sth = $dbh->prepare('SELECT host_id FROM host WHERE target=?');
    	$sth->execute($target);
    	my $id = $sth->fetchrow_array;

    	# if it doesn't exist the in the db, insert it!
    	if ( !$id ) {
    		my $sth = $dbh->prepare( 'INSERT INTO host(target) VALUES(?)');
    		$sth->execute($target);
		
			#TODO: there has to be a better way to do this.
			if ( $dsn =~ /dbi:SQLite/) {
				$id = $dbh->func('last_insert_rowid');
			}
			elsif ( $dsn =~ /dbi:mysql/) {
				$id = $dbh->{'mysql_insertid'};
			}
			else {
			    $sth = $dbh->prepare('SELECT host_id FROM host WHERE target=?');
		    	$sth->execute($target);
	    		$id = $sth->fetchrow_array;
    		}
    	}

		$index_cache{$target} = $id;
    	return $id;
	}
	return $index_cache{$target};
}