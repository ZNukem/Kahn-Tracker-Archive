#!/usr/bin/perl
#
# Kahn Tracker v0.1 - total rewrite of original C tracker in Perl 
# July 12, 2000
# Copyright (C) 2000 Andy Grundman (tiny@descent4.org)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
# new features from old C tracker:
#       now stores servers in a MySQL database
#
# KAHN_TRACKER_INFO_MSG's consist of:	(incoming data)
# 1 byte: P | Q		command
# 4 bytes: 0x61		server version (97)
# 4 bytes: hex		user count
# 1 byte: TYPE		data type (see below)
# 2 bytes: length	length of following data including NULL
# var. bytes: data
# repeat the TYPE/length/data as needed
#
# valid TYPEs:
# STRING_TYPE_NAME                0x01
# STRING_TYPE_OWNER               0x02
# STRING_TYPE_HTTP                0x03
# STRING_TYPE_CLUSTER             0x04
# STRING_TYPE_CHATSERVER  	  0x05
# 
# KAHN_TRACKER_LIST_REQ's consist of:	(outgoing data)
# 7 fields seperated by NULL:
# (hex D1)IP=, USERS=, NAME=, OWNER=, CLUSTER=, HTTP=, CHATSERVER=
# there are 2 NULLs at the end
#	

use IO::Socket;
use strict;
use vars qw($server $server_port $him $datagram $MAX_TO_READ $flags
		$dbh $sth $sql $logfile $timeout $MAX_TRACKER_PACKET);
use DBI;

$server_port = 2224;
$MAX_TO_READ = 100000;
$MAX_TRACKER_PACKET = 1200;	# from kahnd.h
$flags = 0;
$timeout = 120;	# 120 seconds, if a server does not send a INFO_MSG within this amount of time, consider it dead and remove it

$| = 1;

my $debug = 0;
my $logging = 1 if $ARGV[0] ne "--stdout";
$logfile = "perltrack.log";
unlink("input") if (-e "input");

# fork
my $pid;
if (!defined($pid = fork)) {
	writeLog("Error while forking!");
        return;
}

if ($pid) {
        # parent
        print "Launched into background (PID: $pid)\n";
        $SIG{CHLD} = sub { wait; };
	exit(0);

} else {
        # child
	$server = IO::Socket::INET->new(LocalPort => $server_port, Proto => 'udp')
	    or die "Couldn't be a udp server on port $server_port : $@\n";

	while(1) { Run(); }

} 

# main server loop
sub Run {

	# the MySQL server
        my $host = "localhost";
	# the MySQL database table
        my $db = "ktrack";
	# database user
        my $dbuser = "";
	# database password
        my $dbpass = "";
        my $module = "DBI:mysql:$db";
        $dbh = DBI->connect($module,$dbuser,$dbpass);

	# cleanup dead servers before listening for new ones
	cleanup();

	while (my $him = $server->recv($datagram, $MAX_TO_READ, $flags)) {	

	        # call cleanup sub to check for dead servers
	        cleanup();

		my @data = split(/\0/, $datagram);

		my $request = $data[0];
	        my ($remote_port, $ip) = unpack_sockaddr_in($him);
		$ip = inet_ntoa($ip);

		# check the first char received
		# 'P' (0x50): KAHN_TRACKER_INFO_MSG
		# 'Q' (0x51): KAHN_TRACKER_LIST_REQ
		if ($request eq "P") {

			writeLog("INFO_MSG from $ip: $datagram") if $debug;

		        # clean up @data
        		my $version = $data[3];
			my $usercount = $data[6];
			$usercount =~ s/.$//;	# last character is a TYPE, which we don't need
			$usercount = ord($usercount);

        		# find fields and remove first char of each section (it's the length which we don't need)
			my ($x, $name, $admin, $cluster, $url, $chatserver);
			my $chr1 = chr(1);
			my $chr2 = chr(2);
			my $chr3 = chr(3);
			my $chr4 = chr(4);
			my $chr5 = chr(5);

			# this mess is needed because some servers seem to be returning extra seperator characters
			# which in turn causes there to be empty slots in the @data array which must be skipped over
			for ($x = 0; $x < $#data; $x++) {
				if ($data[$x] =~ /$chr1/) {
					$name = ($data[$x+1] ne "") ? $data[$x+1] : $data[$x+2];
					$name =~ s/^.//;
	                        } elsif ($data[$x] =~ /$chr2/) {
	                                $admin = ($data[$x+1] ne "") ? $data[$x+1] : $data[$x+2];
					$admin =~ s/^.//;
	                        } elsif ($data[$x] =~ /$chr3/) {
	                                $url = ($data[$x+1] ne "") ? $data[$x+1] : $data[$x+2];
					$url =~ s/^.//;
	                        } elsif ($data[$x] =~ /$chr4/) {
	                                $cluster = ($data[$x+1] ne "") ? $data[$x+1] : $data[$x+2];
					$cluster =~ s/^.//;
	                        } elsif ($data[$x] =~ /$chr5/) {
	                                $chatserver = ($data[$x+1] ne "") ? $data[$x+1] : $data[$x+2];
					$chatserver =~ s/^.//;
	                        }
		        }
	
			# save the data received from the servers
			if ($debug) {
				open(FILE, ">>input");
				binmode FILE;
				foreach my $line (@data) {
					print FILE $line;
					print FILE "\n";
				}
				print FILE "---\n";
				close(FILE);
			}

			if ($version != 'a') {	# a = 97
				writeLog("Invalid server version: " . $version . ", ignoring") if $debug;
			} else {
				# it's a good server, let's enter it into the database (or update previous entry)
				$sql = "SELECT server_id FROM server WHERE ip = ?";
				$sth = $dbh->prepare($sql);
				$sth->execute($ip);
				my $server_id = $sth->fetchrow;
				my $curtime = time;
				if ($server_id) {	# it was already in, so update the info
					$sql = "UPDATE server SET name=?,admin=?,cluster=?,url=?,chatserver=?,usercount=?,lastupdated=? WHERE server_id = $server_id";
					$sth = $dbh->prepare($sql);
					$sth->execute($name, $admin, $cluster, $url, $chatserver, $usercount, $curtime);
				} else {		# add a new record
					$sql = "INSERT INTO server (name,admin,cluster,url,chatserver,ip,usercount,lastupdated) VALUES " .
						"(?,?,?,?,?,?,?,?)";
					$sth = $dbh->prepare($sql);
					$sth->execute($name, $admin, $cluster, $url, $chatserver, $ip, $usercount, $curtime);
					writeLog("Added new server $name ($ip)") if $debug;
				}

			}
		
		} elsif ($request eq "Q") {
			writeLog("LIST_REQ from $ip") if $debug;
			# LIST_REQ stuff

			# info string that we send to client
			my $info = "Ñ";	# hex D1

			# get database info
			$sql = "SELECT name,admin,cluster,url,chatserver,ip,usercount FROM server";
			$sth = $dbh->prepare($sql);
			$sth->execute();
			my ($server_ip, $usercount, $name, $admin, $cluster, $url, $chatserver);
			$sth->bind_columns(undef, \$name, \$admin, \$cluster, \$url, \$chatserver, \$server_ip, \$usercount);
			while ($sth->fetch) {
				$info .= "IP=$server_ip\0";
				$info .= "USERS=$usercount\0";
				$info .= "NAME=$name\0";
				$info .= "OWNER=$admin\0";
				$info .= "CLUSTER=$cluster\0";
				$info .= "HTTP=$url\0";
				$info .= "CHATSERVER=$chatserver\0";
			}
			$info .= "\0";

			# send the data back to the user
			sendTrackerList($ip, $remote_port, $info);

		} else {
			writeLog("Invalid request: $request from $ip") if $debug;
		}

	} # end of while loop

# we should never get here, but just in case...
$server->close();
return 0;

}

#
# simple logging function
#
sub writeLog {
	my $logmsg = shift;
	if ($logging) {
		open LOGFILE, ">>$logfile";
		print LOGFILE "$logmsg\n";
		close LOGFILE;
	} else {
		print "$logmsg\n";
	}
}

#
# sends tracker list via UDP to an IP address
#
sub sendTrackerList {

	my $ip = shift;
	my $remote_port = shift;
	my $info = shift;

	$| = 1;
	my $client = IO::Socket::INET->new(
		PeerAddr => $ip,
		PeerPort => $remote_port,
                Proto => 'udp')
	    or writeLog("Couldn't send udp to $ip on port $remote_port : $@\n");

	# there is code in the original C program that seems to buffer data every 1200 characters
	# however, this data does not appear to need buffering, as my Kahn client receives > 1200 
	# packets without any trouble.

	# buffer $info if > MAX_TRACKER_PACKET (-2 because of C null and hex D1 char)
#	if (length($info) > $MAX_TRACKER_PACKET - 2) {
#	        my $offset = 0;
#	        while ( (length($info) - $offset) > 0) {
#	                my $temp = substr($info, $offset, $MAX_TRACKER_PACKET - 2);
#	                $offset += ($MAX_TRACKER_PACKET - 2);
#			if ($temp !~ /^Ñ/) {
#				$temp = "Ñ" . $temp;
#			}
#	                print $client $temp;
#			writeLog("Sent chunk $temp to $ip:$remote_port (offset: $offset)") if $debug;
#	        }
#	} else {
		print $client $info;
		writeLog("Sent $info to $ip:$remote_port") if $debug;
#	}	
	
	$client->close();

}

#
# cleanup checks for servers that haven't responded within the timeout period
#
sub cleanup {

	my $curtime = time;
	$sql = "SELECT server_id,name,ip,lastupdated FROM server";
	$sth = $dbh->prepare($sql);
	$sth->execute();
	my ($server_id, $name, $ip, $lastupdated);
	$sth->bind_columns(undef, \$server_id, \$name, \$ip, \$lastupdated);
	while ($sth->fetch) {
		if ( ($curtime - $lastupdated) > $timeout) {
			# server died!
			my $sqla = "DELETE FROM server WHERE server_id = $server_id";
			my $sta = $dbh->prepare($sqla);
			$sta->execute();
			writeLog("Removed dead server $name ($ip)") if $debug;
		}
	}

}
