# Plugin.pm - Kahn tracker/user data plugin for perlbot (http://www.pas.rochester.edu/~burke/perlbot/)
# version 0.1 / Feb 1 2000
# Andy Grundman (tiny@descent4.org)
# -- thanks to Observer for helping me with the user listings
#
# TODO:
#   user listings from other servers besides Stargate
#   sort user listings
#
# INSTALL:
#   create a directory under perlbot/plugins called Kahn.
#   place Plugin.pm in the Kahn directory.
#   perlbot will recognize it automatically.
#
package Kahn::Plugin;

use Perlbot;
use Socket;
use POSIX;
use Text::ParseWords;

sub get_hooks {
  return { public => \&on_public, msg => \&on_msg };
}

# no public support allowed
sub on_public {
#  my $conn = shift;
#  my $event = shift;
#  my $args;
#
#  ($args = $event->{args}[0]) =~ tr/[A-Z]/[a-z]/;
#
#  if($args =~ /^!kahn/) {
#    get_kahn($conn, $event, $event->{to}[0]);
#  }
}

sub on_msg {
  my $conn = shift;
  my $event = shift;
  my $args;
 
  ($args = $event->{args}[0]) =~ tr/[A-Z]/[a-z]/;

  get_kahn($conn, $event, $event->nick);
}

sub get_kahn {
  my $conn = shift;
  my $event = shift;
  my $who = shift;

  if(!defined($pid = fork)) {
    $conn->privmsg($chan, "error in kahn plugin...");
    return;
  }

  if($pid) {
    #parent

    $SIG{CHLD} = sub { wait; };
    return;

  } else {
    # child

    my $args;
    ($args = $event->{args}[0]) =~ tr/[A-Z]/[a-z]/;
    
    my ($command, $arg1, $arg2, $arg3) = split(' ', $args);

    if ($command eq "help") {
	$conn->privmsg($who, "Hi, I'm the Kahn tracker bot!");
	$conn->privmsg($who, " -- coded by Tiny, with thanks to Observer");
	$conn->privmsg($who, "Usage: /msg Tracker servers [dns]");
	$conn->privmsg($who, "          - shows all populated Kahn servers");
	$conn->privmsg($who, "       /msg Tracker users Stargate [dns]");
	$conn->privmsg($who, "          - shows all users on the Stargate server");
	$conn->privmsg($who, "       (specify dns to resolve all IP addresses)");
	$conn->{_connected} = 0;
        exit 0;
  }

if ($arg1 =~ /stargate/) {

	my $tracker_ip = "209.95.105.4";
	my $tracker_port = 2210;

	my $local_address = gethostbyname("stargatenetworks.com");
	my $protocol = getprotobyname('udp');
	my $packed_local_address = sockaddr_in(0, $local_address);
	socket(SOCKET, AF_INET, SOCK_DGRAM, $protocol) || die "socket: $? $!";
	#bind(SOCKET, $packed_local_address) || die "bind: $? $!";
	$| = 1;
	my $tracker_address = inet_aton($tracker_ip) || die "unknown host";
	my $packed_tracker_address = sockaddr_in($tracker_port, $tracker_address);
	defined(send(SOCKET, "?", 0, $packed_tracker_address)) || die "send: $? $!";
	my $rin = '';
	vec($rin, fileno(SOCKET), 1) = 1;
	while (select(my $rout = $rin, undef, undef, 5.0)) {
		($packed_tracker_address = recv(SOCKET, $receive_tracker_data, 100000, 0)) || die "recv: $? $!";
		push @tracker_data, substr($receive_tracker_data,1);
	}
	close(SOCKET);

	my $count = 0;

	my @users = quotewords("\000",0,$tracker_data[0]);

	@allusers = ();

	$total_users = 0;
	my $x = 0;
	while ($users[$x]) {
		$value = $users[$x];
		chomp($value);
		$count++;
		if ($count == 1) {
		$allusers[$total_users] = "";
		$allusers[$total_users] .= "$value";
		} elsif ($count == 2) {
			if ($arg2 =~ /dns/) {
				$value = gethostbyaddr(inet_aton($value), AF_INET);
			}
			$allusers[$total_users] .= " ($value)";
		} elsif ($count == 3) {
			$allusers[$total_users] .= " running $value";
		} elsif ($count == 4) { # ignore reg status
		} elsif ($count == 5) { # ignore op value
			$count = 0;
			$total_users++;
		}
		$x++;
	}

} else {

	my $tracker_ip = "209.95.105.4";
	my $tracker_port = 2224;

	my $protocol = getprotobyname('udp');
	socket(SOCKET, AF_INET, SOCK_DGRAM, $protocol) || $conn->privmsg($who, "socket error");
	$| = 1;
	my $tracker_address = inet_aton($tracker_ip) || $conn->privmsg($who, "unknown host");
	my $packed_tracker_address = sockaddr_in($tracker_port, $tracker_address);
	defined(send(SOCKET, "Q", 0, $packed_tracker_address)) || $conn->privmsg($who, "send failed");
	my $rin = '';
	vec($rin, fileno(SOCKET), 1) = 1;
	while (select(my $rout = $rin, undef, undef, 5.0)) {
		($packed_tracker_address = recv(SOCKET, $receive_tracker_data, 100000, 0)) || $conn->privmsg($who, "recv failed");
		push @tracker_data, substr($receive_tracker_data,1);
	}
	close(SOCKET);

	my $server_count = 0;
	PACKET: foreach $i (0 .. $#tracker_data) {
		my $count = 0;
		my($ip,$user_count,$name,$owner,$chat_server,$cluster,$url) = ();
		foreach $tracker_entry (split(/\000/,$tracker_data[$i])) {
			$count++;
			my($type,$value) = split(/=/,$tracker_entry,2);
			if (($type eq "IP") && ($count > 1)) {
				$servers{$ip} = "$ip       $user_count       $name       $owner       $chat_server       $cluster       $url";
				$server_count++;
			}
			if ($type eq "IP") {
				$ip = $value;
			} elsif ($type eq "USERS") {
				$user_count = $value;
			} elsif ($type eq "NAME") {
				$name = $value;
			} elsif ($type eq "OWNER") {
				$owner = $value;
			} elsif ($type eq "CHATSERVER") {
				$chat_server = $value;
			} elsif ($type eq "CLUSTER") {
				$cluster = $value;
			} elsif ($type eq "HTTP") {
				$url = $value;
			}
		}
		$servers{$ip} = "$ip       $user_count       $name       $owner       $chat_server       $cluster       $url";
		$server_count++;
	}

}

if ($command =~ /servers/) {
	foreach $server (sort SortServers keys(%servers)) {
    	my($ip,$user_count,$name,$owner,$chat_server,$cluster,$url) = split(/       /,$servers{$server});
   		if ($user_count gt 0) {	# populated servers
 			my $dns = $ip;
			if ($arg1 =~ /dns/) {
				$dns = gethostbyaddr(inet_aton($ip), AF_INET);
				if ($dns =~ /gideon\.lightrealm\.com/) { $dns = "stargatenetworks.com"; }
			}
			$conn->privmsg($who, "$name ($dns) Users: $user_count");
		}
	}

} elsif ($arg1 =~ /stargate/) {
	$conn->privmsg($who, "Total users on Stargate: $total_users");
	for ($i = 0; $i < $total_users; $i++) {
		$conn->privmsg($who, "  $allusers[$i]");
	}

} else {
	$conn->privmsg($who, "Invalid command: $command $arg1 $arg2 $arg3");
}

    $conn->{_connected} = 0;
    exit 0;
  }
}


sub SortServers {
    my($a_ip,$a_user_count,$a_name,$a_owner,$a_chat_server,$a_cluster,$a_url) = split(/       /,$servers{$a});
    my($b_ip,$b_user_count,$b_name,$b_owner,$b_chat_server,$b_cluster,$b_url) = split(/       /,$servers{$b});
    if (($a_user_count == 0) && ($b_user_count == 0)) {
        if ($a_name eq $b_name) {
            return ($a_ip cmp $b_ip);
        } else {
            return ($a_name cmp $b_name);
        }
    } else {
        if ($a_user_count == $b_user_count) {
            if ($a_name eq $b_name) {
                return ($a_ip cmp $b_ip);
            } else {
                return ($a_name cmp $b_name);
            }
        } else {
            return ($b_user_count <=> $a_user_count);
        }
    }
}

1;
