#!/usr/bin/perl
#
# kahnt.cgi - Web-based Kahn Server/User Listing
# version 0.2 / Feb 3 2000
# Andy Grundman (tiny@descent4.org)
# -- thanks to Observer for helping me with the user listings
# (based on an early version by Norm Bright)
#
# TODO:
#   sort user listings
#
require 5.003;
use strict;
use Socket;
use Text::ParseWords;

my(%servers, @tracker_data, $tracker_entry, $receive_tracker_data, $i, $server);
print "Content-type: text/html\n\n";
open(STDERR, ">&STDOUT") || die "Can't dup stdout: $!";
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

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

sub show_users {

	my(@user_data, $receive_user_data);

	my $user_ip = $_[0];
	my $user_port = 2210;

	my $error = 0;

	my $user_protocol = getprotobyname('udp');
	socket(SOCKET, AF_INET, SOCK_DGRAM, $user_protocol) || die "socket: $? $!";
	$| = 1;
	my $user_address = inet_aton($user_ip) || die "unknown host";
	my $packed_user_address = sockaddr_in($user_port, $user_address);
	defined(send(SOCKET, "?", 0, $packed_user_address)) || die "send: $? $!";
	my $rin = '';
	vec($rin, fileno(SOCKET), 1) = 1;
	while (select(my $rout = $rin, undef, undef, 5.0)) {
		if (!($packed_user_address = recv(SOCKET, $receive_user_data, 100000, 0))) { 
		$error = 1;
		}
		push @user_data, substr($receive_user_data,1);
	}
	close(SOCKET);

	if ($error == 1) {
		print "<tr><td><small><ul><li>No response from server</li></ul></small></td></tr>\n";
	} else {
		my $count = 0;
		my @users = quotewords("\000",0,$user_data[0]);
		my @allusers = ();

		my $total_users = 0;
		my $x = 0;
		while ($users[$x]) {
			my $value = $users[$x];
			chomp($value);
			$count++;
			if ($count == 1) {
				$allusers[$total_users] = "";
				$allusers[$total_users] .= "$value";
			} elsif ($count == 2) { # ignore IP (don't want to show IP's on a webpage!)
			} elsif ($count == 3) {
				$allusers[$total_users] .= ", running $value";
			} elsif ($count == 4) { # ignore reg status
			} elsif ($count == 5) { # ignore op value
				$count = 0;
				$total_users++;
			}
			$x++;
		}

		print "<tr><td><small><ul>\n";
		for (my $i = 0; $i < $total_users; $i++) {
				print "<li>$allusers[$i]</li>\n";
		}
		print "</ul></small></td></tr>\n";
	}
}

my $tracker_ip = "209.95.105.4";
my $tracker_port = 2224;

my $protocol = getprotobyname('udp');
socket(SOCKET, AF_INET, SOCK_DGRAM, $protocol) || die "socket: $? $!";
$| = 1;
my $tracker_address = inet_aton($tracker_ip) || die "unknown host";
my $packed_tracker_address = sockaddr_in($tracker_port, $tracker_address);
defined(send(SOCKET, "Q", 0, $packed_tracker_address)) || die "send: $? $!";
my $rin = '';
vec($rin, fileno(SOCKET), 1) = 1;
while (select(my $rout = $rin, undef, undef, 5.0)) {
    ($packed_tracker_address = recv(SOCKET, $receive_tracker_data, 100000, 0)) || die "recv: $? $!";
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

# begin HTML display
print qq~
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2//EN">

<html>
<head>
<title>Kahn Servers and Users</title>
<meta NAME="Author" CONTENT="Andy Grundman (tiny\@descent4.org">
<meta NAME="Generator" CONTENT="vi :)">

</head>

<body BGCOLOR="#000000" LINK="#FFFF00" VLINK="#00FF00" TEXT="#FFFFFF">

<table CELLPADDING="0" CELLSPACING="0" BORDER="0" WIDTH="605">
<tr VALIGN="top" ALIGN="left">
<td>

  <table BORDER="0" CELLSPACING="0" CELLPADDING="0" WIDTH="180">
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="100"><img SRC="../assets/auto_generated_images/img_15b94aa0.gif" WIDTH="180" HEIGHT="1" BORDER="0"></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="45" ALIGN="left" VALIGN="top"><a HREF="../"><img HEIGHT="45" WIDTH="180" SRC="../assets/images/Home_Button.gif" BORDER="0" ALT="Home"></a></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="45" ALIGN="left" VALIGN="top"><a HREF="../html/about.html"><img HEIGHT="45" WIDTH="180" SRC="../assets/images/About_Button.gif" BORDER="0" ALT="About"></a></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="45" ALIGN="left" VALIGN="top"><a HREF="../html/files.html"><img HEIGHT="45" WIDTH="180" SRC="../assets/images/Files_Button.gif" BORDER="0" ALT="Files"></a></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="45" ALIGN="left" VALIGN="top"><img HEIGHT="45" WIDTH="180" SRC="../assets/images/Kahn_Servers_Button_On.gif" BORDER="0" ALT="Kahn Servers"></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="45" ALIGN="left" VALIGN="top"><a HREF="../html/faq.html"><img HEIGHT="45" WIDTH="180" SRC="../assets/images/FAQ_Button.gif" BORDER="0" ALT="FAQ"></a></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="45" ALIGN="left" VALIGN="top"><a HREF="../html/register.html"><img HEIGHT="45" WIDTH="180" SRC="../assets/images/Register_Button.gif" BORDER="0" ALT="Register"></a></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="45" ALIGN="left" VALIGN="top"><a HREF="../html/links.html"><img HEIGHT="45" WIDTH="180" SRC="../assets/images/Links_Button.gif" BORDER="0" ALT="Links"></a></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="180" HEIGHT="45" ALIGN="left" VALIGN="top"><a HREF="../html/credits.html"><img HEIGHT="45" WIDTH="180" SRC="../assets/images/Credits_Button.gif" BORDER="0" ALT="Credits"></a></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td HEIGHT="25"></td>
   </tr>
  </table>
</td>
<td>

  <table BORDER="0" CELLSPACING="0" CELLPADDING="0" WIDTH="425">
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="400" HEIGHT="100"><img HEIGHT="100" WIDTH="400" SRC="../assets/auto_generated_images/img_15baef84.jpg" BORDER="0" ALT="   Kahn
Servers "></td>
        <td WIDTH="25"><img SRC="../assets/auto_generated_images/img_15b94aa0.gif" WIDTH="25" HEIGHT="1" BORDER="0"></td>
   </tr>
   <tr VALIGN="top" ALIGN="left">
        <td WIDTH="425" COLSPAN="2"><p><font FACE="Arial,Helvetica">This is a dynamic list of active Kahn servers and users, retrieved straight from our tracker service.&nbsp; </font><a HREF="../html/files.html"><font FACE="Arial,Helvetica">Download Kahn now</font></a><font FACE="Arial,Helvetica"> so you can connect to one and join the fun!</font></p><p>&nbsp;</td>

   </tr>
   <tr VALIGN="top" ALIGN="left">
   <TABLE>
   <TR><TH><FONT FACE=\"Arial,Helvetica\">Game Servers</FONT></TH><TH><FONT FACE=\"Arial,Helvetica\">IP Address</FONT></TH><TH><FONT FACE=\"Arial,Helvetica\">Users</FONT></TH></TR>
~;
foreach $server (sort SortServers keys(%servers)) {
    my($ip,$user_count,$name,$owner,$chat_server,$cluster,$url) = split(/       /,$servers{$server});
    print "<TR><TD><A HREF=\"$url\"><FONT FACE=\"Arial,Helvetica\">$name</FONT></A></TD><TD><FONT FACE=\"Arial,Helvetica\">$ip</FONT></TD><TD><FONT FACE=\"Arial,Helvetica\">$user_count</FONT></TD></TR>\n";
    $user_count =~ s/^\s+//;
    $user_count =~ s/\s+$//;
    if ($user_count > 0) {
    	&show_users($ip);
    }
}
print qq~
<tr><th><br><br><font face="Arial,Helvetica">Chat Servers</font></th><th><br><br><font face="Arial,Helvetica">IP Address</font></th><th><br><br><font face="Arial,Helvetica">Port</font></th></tr>
<tr><td><font face="Arial,Helvetica">Main Stargate IRC Server</font></td><td><font face="Arial,Helvetica">209.95.105.4</font></td><td><font face="Arial,Helvetica">6969
</font></td></tr>
</table></center>
</tr></table></td></tr></table>
</body></html>
~;

