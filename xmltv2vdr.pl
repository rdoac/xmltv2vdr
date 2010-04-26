#!/usr/bin/perl

# xmltv2vdr.pl
#
# Converts data from an xmltv output file to VDR - tested with 1.2.6
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

# $Id: xmltv2vdr.pl 1.0.6 2004/04/19 20:01:04 psr Exp $


use Getopt::Std;
use Time::Local;
use Date::Manip;


# Translate HTML/XML encodings into normal characters
# For some German problems, and also English

sub xmltvtranslate
{
  $line=shift;

  # German Requests - mail me with updates if some of these are wrong..

  $line=~s/ und uuml;/ü/g;
  $line=~s/ und auml;/ä/g; 
  $line=~s/ und ouml;/ö/g;
  $line=~s/ und quot;/"/g; 
  $line=~s/ und szlig;/ß/g; 
  $line=~s/ und amp;/\&/g; 
  $line=~s/ und middot;/·/g; 
  $line=~s/ und Ouml;/Ö/g; 
  $line=~s/ und Auml;/Ä/g;
  $line=~s/ und Uuml;/Ü/g ;
  $line=~s/ und eacute;/é/g;
  $line=~s/ und aacute;/á/g;
  $line=~s/ und deg;/°/g;
  $line=~s/ und ordm;/º/g;
  $line=~s/ und ecirc;/ê/g;
  $line=~s/ und ecirc;/ê/g;
  $line=~s/ und ccedil;/ç/g;
  $line=~s/ und curren;/¤/g;
  $line=~s/und curren;/¤/g;
  $line=~s/und Ccedil;/Ç/g;
  $line=~s/ und ocirc;/ô/g;
  $line=~s/ und egrave;/è/g;
  $line=~s/ und agrave;/à/g;
  $line=~s/und quot;/"/g;
  $line=~s/und Ouml;/Ö/g;
  $line=~s/und Uuml;/Ü/g;
  $line=~s/und Auml;/Ä/g;
  $line=~s/und ouml;/ö/g;
  $line=~s/und uuml;/ü/g;
  $line=~s/und auml;/ä/g;
 
  # English - only ever seen a problem with the Ampersand character..

  $line=~s/&amp;/&/g;
 
  return $line;
}



# Convert XMLTV time format (YYYYMMDDmmss ZZZ) into VDR (secs since epoch)

sub xmltime2vdr
{
  my $xmltime=shift;
  my $skew=shift;
  $secs = &Date::Manip::UnixDate($xmltime, "%s");
  return $secs + ( $skew * 60 );
}

# Send info over SVDRP (thanks to Sky plugin)

sub SVDRPsend
{
  my $s = shift;
  if ($sim == 0)
  {
    print SOCK "$s\r\n";
  }
  else 
  {
    print "$s\r\n";
  } 
}

# Recv info over SVDRP (thanks to Sky plugin)

sub SVDRPreceive
{
  my $expect = shift | 0;

  if ($sim == 1)
  { return 0; }

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

  # Split a Chan Line
  
  chomp $chanline;
 
  ($channel_name, $freq, $param, $source, $srate, $vpid, $apid, $tpid, $ca, $sid, $nid, $tid, $rid, $xmltv_channel_name) = split(/:/, $chanline);

  if ( $source eq 'T' )
  { 
     $epgfreq=substr($freq, 0, 3);
  }
  else
  { 
     $epgfreq=$freq;
  }

  if (!$xmltv_channel_name) {
      if(!$channel_name) {
	  $chanline =~ m/:(.*$)/;
	  if ($verbose == 1 ) { warn("Ignoring header: $1\n"); }
      } else {
	  if ($verbose == 1 ) { warn("Ignoring channel: $channel_name, no xmltv info\n"); } 
      }
      next;
  }

  # Send VDR PUT EPG
  SVDRPsend("PUTE");
  SVDRPreceive(354);

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
     $xmlline=xmltvtranslate($xmlline);

     # New XML Program - doesn't handle split programs yet
     if ( ($xmlline =~ /\<programme/ ) && ( $xmlline =~ /\"$xmltv_channel_name/ ) && ( $xmlline !~ /clumpidx=\"1\/2\"/ ) && ( $chanevent == 0 ) )
     {  
       $chanevent = 1;
       ( $null, $xmlst, $null, $xmlet, @null ) = split(/\"/, $xmlline);
       $vdrst = &xmltime2vdr($xmlst, $adjust);
       $vdret = &xmltime2vdr($xmlet, $adjust);
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

  # Send End of Channel, and end of EPG data

  SVDRPsend("c");
  SVDRPsend(".");
  SVDRPreceive(250);
}
}

#---------------------------------------------------------------------------
# main

use Socket;

$Usage = qq{
Usage: $0 [options] -c <channels.conf file> -x <xmltv datafile> 

Options:
	 -a (+,-) mins  	Adjust the time from xmltv that is fed
				into VDR (in minutes) (default: 0)	 
	 -c channels.conf	File containing modified channels.conf info
	 -d hostname            destination hostname (default: localhost)
	 -h			Show help text
	 -l description length  Verbosity of EPG descriptions to use
                                (0-2, 0: more verbose, default: 0)
         -p port                SVDRP port number (default: 2001)
	 -s			Simulation Mode (Print info to stdout)
         -t timeout             The time this program has to give all info to 
				VDR (default: 300s) 
	 -v             	Show warning messages
	 -x xmltv output 	File containing xmltv data

};

$sim=0;


die $Usage if (!getopts('a:d:p:l:t:x:c:vhs') || $opt_h);

$verbose = 1 if $opt_v;
$sim = 1 if $opt_s;
$adjust = $opt_a || 0;
$Dest   = $opt_d || "localhost";
$Port   = $opt_p || 2001;
$descv   = $opt_l || 0;
$Timeout = $opt_t || 300; # max. seconds to wait for response
$xmltvfile = $opt_x  || die "$Usage Need to specify an XMLTV file";
$channelsfile = $opt_c  || die "$Usage Need to specify a channels.conf file";

# Check description value

if ( ( $descv < 0 ) || ( $descv > 2 ) )
{
  die "$Usage Description out of range. Try 0 - 2";
}

# Read all the XMLTV stuff into memory - quicker parsing

open(XMLTV, "$xmltvfile") || die "cannot open xmltv file";
@xmllines=<XMLTV>;
close(XMLTV);

# Now open the VDR channel file

open(CHANNELS, "$channelsfile") || die "cannot open channels.conf file";

# Connect to SVDRP socket (thanks to Sky plugin coders)

if ( $sim == 0 )  
{
  $SIG{ALRM} = sub { die("timeout"); };
  alarm($Timeout);

  $iaddr = inet_aton($Dest)                   || die("no host: $Dest");
  $paddr = sockaddr_in($Port, $iaddr);

  $proto = getprotobyname('tcp');
  socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die("socket: $!");
  connect(SOCK, $paddr)                       || die("connect: $!");
  select((select(SOCK), $| = 1)[0]);
}

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
