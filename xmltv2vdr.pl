#!/usr/bin/perl

# xmltv2vdr.pl
#
# Converts data from an xmltv output file to VDR
#
# The TCP SVDRSend and Receive functions have been used from the getskyepg.pl
# Plugin for VDR.
#
# This script requires: -
#
# The PERL module date::manip (required for xmltv anyway)
#
# You will also need xmltv installed to get the channel information:
# http://sourceforge.net/projects/xmltv
#
# This software is released under the GNU GPL
#
# See the README file for copyright information and how to reach the author.

# $Id: xmltv2vdr.pl 1.0.3 2003/05/01 12:23:00 psr Exp $


use Getopt::Std;
use Time::Local;
use Date::Manip;

# Convert XMLTV time format (YYYYMMDDmmss ZZZ) into VDR (secs since epoch)

sub xmltime2vdr
{
  my $xmltime=shift;
  $secs = &Date::Manip::UnixDate($xmltime, "%s");
  return $secs;
}

# Send info over SVDRP (thanks to Sky plugin)

sub SVDRPsend
{
  my $s = shift;
  print SOCK "$s\r\n";
}

# Recv info over SVDRP (thanks to Sky plugin)

sub SVDRPreceive
{
  my $expect = shift | 0;
  my @a = ();
  while (<SOCK>) {
        s/\s*$//; # 'chomp' wouldn't work with "\r\n"
        push(@a, $_);
        if (substr($_, 3, 1) ne "-") {
           my $code = substr($_, 0, 3);
           die("expected SVDRP code $expect, but received $code") if ($code != $expect);
           last;
           }
        }
  return @a;
}

# Process info from XMLTV file / channels.conf and send via SVDRP to VDR

sub ProcessEpg
{

while ( $chanline=<CHANNELS> )
{
  $desccount = shift; # Verbosity

  # Send VDR PUT EPG
  SVDRPsend("PUTE");
  SVDRPreceive(354);

  # Split a Chan Line
  
  chomp $chanline;
 
  ($channel_name, $freq, $param, $source, $srate, $vpid, $apid, $tpid, $ca, $sid, $nid, $tid, $rid, $xmltv_channel_name) = split(/:/, $chanline);
  $epgfreq=substr($freq, 0, 3);


  # Send a Channel Entry
  if ($nid>0) 
  {
     SVDRPsend("C $source-$nid-$tid-$sid $channel_name");
  }
  else 
  {
     SVDRPsend("C $source-$nid-$epgfreq-$sid $channel_name");
  }

  # Set XML parsing variables

  $chanevent = 0;
  $dc = 0;
  $founddesc=0;

  # Find XML events

  foreach $xmlline (@xmllines)
  {
     chomp $xmlline;

     # New XML Program - doesn't handle split programs yet

     if ( ($xmlline =~ /\<programme/ ) && ( $xmlline =~ /$xmltv_channel_name/ ) && ( $xmlline !~ /clumpidx=\"1\/2\"/ ) && ( $chanevent == 0 ) )
     {  
       $chanevent = 1;
       ( $null, $xmlst, $null, $xmlet, @null ) = split(/\"/, $xmlline);
       $vdrst = &xmltime2vdr($xmlst);
       $vdret = &xmltime2vdr($xmlet);
       $vdrdur = $vdret - $vdrst;
       $vdrid = $vdrst / 60 % 0xFFFF;
       
       # Send VDR Event
       SVDRPsend("E $vdrid $vdrst $vdrdur 0");
     }

     # XML Program Title

     if ( ($xmlline =~ /\<title/ ) && ( $chanevent == 1 ) )
     {
       #print $xmlline . "\n";
       ( $null, $tmp ) = split(/\>/, $xmlline);
       ( $vdrtitle, @null ) = split(/\</, $tmp);
  
       # Send VDR Title

       SVDRPsend("T $vdrtitle");
     }

     # XML Program description at required verbosity

     if ( ($xmlline =~ /\<desc/ ) && ( $chanevent == 1 ) && ( $desccount == $dc ))
     {
       ( $null, $tmp ) = split(/\>/, $xmlline);
       ( $vdrdesc, @null ) = split(/\</, $tmp);
 
       # Send VDR Description

       SVDRPsend("D $vdrdesc");

       # Send VDR end of event

       SVDRPsend("e");
       $dc++;
       $founddesc=1
     }

     # Description is not required verbosity
     
     if ( ($xmlline =~ /\<desc/ ) && ( $chanevent == 1 ) && ( $desccount != $dc ))
     { 
       $dc++;
     }

     # No Description found at required verbosity

     if ( ($xmlline =~ /\<\/programme/ ) && ( $chanevent == 1 ) )
     {
       if ( $founddesc == 0 )
       { 
	 SVDRPsend("D Info Not Available");
         SVDRPsend("e");
       }
       $chanevent=0 ;
       $dc=0 ;
       $founddesc=0 ;
     }
  }

  # Send End of Event, End of Channel, and end of EPG data

  SVDRPsend("c");
  SVDRPsend(".");
  SVDRPreceive(250);
}
}

#---------------------------------------------------------------------------
# main

use Socket;

$Usage = qq{
Usage: $0 [options]

Options: -d hostname            destination hostname (default: localhost)
         -p port                SVDRP port number (default: 2001)
	 -l description length  Verbosity of EPG descriptions to use
                                (0-2, 0: more verbose, default: 0)
	 -x xmltv output file 
	 -c modified channels.conf file	
};

die $Usage if (!getopts("x:c:l:") || $opt_h);

$Dest   = $opt_d || "localhost";
$Port   = $opt_p || 2001;
$descv   = $opt_l || 0;
$xmltvfile = $opt_x  || die "$Usage Need to specify an XMLTV file";
$channelsfile = $opt_c  || die "$Usage Need to specify a channels.conf file";

# Check description value

if ( ( $descv < 0 ) || ( $descv > 2 ) )
{
  die "$Usage Description out of range. Try 0 - 2";
}

$Timeout = 300; # max. seconds to wait for response

# Read all the XMLTV stuff into memory - quicker parsing

open(XMLTV, "$xmltvfile") || die "cannot open xmltv file";
@xmllines=<XMLTV>;
close(XMLTV);

# Now open the VDR channel file

open(CHANNELS, "$channelsfile") || die "cannot open channels.conf file";

# Connect to SVDRP socket (thanks to Sky plugin coders)
  
$SIG{ALRM} = sub { die("timeout"); };
alarm($Timeout);

$iaddr = inet_aton($Dest)                   || die("no host: $Dest");
$paddr = sockaddr_in($Port, $iaddr);

$proto = getprotobyname('tcp');
socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die("socket: $!");
connect(SOCK, $paddr)                       || die("connect: $!");
select(SOCK); $| = 1;

# Look for initial banner
SVDRPreceive(220);
SVDRPsend("CLRE");
SVDRPreceive(250);

# Do the EPG stuff
ProcessEpg($descv);

# Lets get out of here! :-)
SVDRPsend("QUIT");
SVDRPreceive(221);

close(SOCK);
