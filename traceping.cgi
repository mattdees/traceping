#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;

use DBI;
use DBD::SQLite;

my $dsn = "dbi:SQLite:dbname=/tmp/test.sqlite";
my $db_username = '';
my $db_password = '';


print "Content-Type: text/html\r\n\r\n";

my $target;

# Validate input
if ( $ENV{'QUERY_STRING'} =~ /^target=([a-zA-Z0-9._-]+)$/ ) {
	$target = $1;
}
else {
	print 'lolol DIAF';
	exit 1;
}

print '<div id="traceroute"><pre style="width: 900px; overflow: auto;">' . get_traceroute($target) . '</pre></div>';

sub get_traceroute {
	my ( $target ) = @_;
    my $dbh = DBI->connect($dsn, $db_username, $db_password);    
    my $sth = $dbh->prepare('SELECT tracert FROM host WHERE target=?');
    $sth->execute($target);
    my $result = $sth->fetchrow_array;
    if ( $result ) {
    	return $result;
    }
    return 'No Traceroute Data Found';
}

