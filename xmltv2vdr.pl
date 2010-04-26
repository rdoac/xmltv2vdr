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

# $Id: xmltv2vdr.pl 1.0.7 2007/04/13 20:01:04 psr Exp $


#use strict;
use Getopt::Std;
use Time::Local;
use Date::Manip;

my $sim=0;
my $verbose=0;
my $adjust;
my @xmllines;

# Translate HTML/XML encodings into normal characters
# For some German problems, and also English

sub xmltvtranslate
{
    my $line=shift;
    
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

# English - found in Radio Times data

    $line=~s/&#8212;/--/g;
    $line=~s/&lt;BR \/&gt;/|/g;    

    return $line;
}



# Convert XMLTV time format (YYYYMMDDmmss ZZZ) into VDR (secs since epoch)

sub xmltime2vdr
{
    my $xmltime=shift;
    my $secs = &Date::Manip::UnixDate($xmltime, "%s");
    return $secs + ( $adjust * 60 );
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

sub EpgSend 
{
    my ($p_chanId, $p_chanName, $p_epgText, $p_nbEvent) = @_;
    # Send VDR PUT EPG
    SVDRPsend("PUTE");
    SVDRPreceive(354);
    SVDRPsend($p_chanId . $p_epgText . "c\r\n" . ".");
    SVDRPreceive(250);
    if ($verbose == 1 ) { warn("$p_nbEvent event(s) sent for $p_chanName\n"); }
}

# Process info from XMLTV file / channels.conf and send via SVDRP to VDR

sub ProcessEpg
{
    my %chanId;
    my %chanName;
    my %chanMissing;
    my $chanline;
    my $epgfreq;
    while ( $chanline=<CHANNELS> )
    {
        # Split a Chan Line
        
        chomp $chanline;
        
        my ($channel_name, $freq, $param, $source, $srate, $vpid, $apid, $tpid, $ca, $sid, $nid, $tid, $rid, $xmltv_channel_name) = split(/:/, $chanline);
        
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
        my @channels = split ( /,/, $xmltv_channel_name);
        foreach my $myChannel ( @channels )
        {
        	$chanName{$myChannel} = $channel_name;
        	# Save the Channel Entry
        	if ($nid>0) 
        	{
                $chanId{$myChannel} = "C $source-$nid-$tid-$sid $channel_name\r\n";
        	}
        	else 
        	{
                $chanId{$myChannel} = "C $source-$nid-$epgfreq-$sid $channel_name\r\n";
        	}
        }
    }
    
    # Set XML parsing variables    
    my $chanevent = 0;
    my $dc = 0;
    my $founddesc=0;
    my $chanCur = "";
    my $nbEventSent = 0;
    my $atLeastOneEpg = 0;
    my $epgText = "";
    my $pivotTime = time ();
    my $xmlline;
    
    # Find XML events
    
    foreach $xmlline (@xmllines)
    {
        chomp $xmlline;
        $xmlline=xmltvtranslate($xmlline);
        
        # New XML Program - doesn't handle split programs yet
        if ( ($xmlline =~ /\<programme/o ) && ( $xmlline !~ /clumpidx=\"1\/2\"/o ) && ( $chanevent == 0 ) )
        {
            my ( $chan ) = ( $xmlline =~ m/channel\=\"(.*?)\"/ );
            if ( !exists ($chanId{$chan}) )
            {
                if ( !exists ($chanMissing{$chan}) )
                {
                    if ($verbose == 1 ) { warn("$chan unknown in channels.conf\n"); }
                    $chanMissing{$chan} = 1;
                }
                next;
            }
            my ( $xmlst, $xmlet ) = ( $xmlline =~ m/start\=\"(.*?)\"\s+stop\=\"(.*?)\"/o );
            my $vdrst = &xmltime2vdr($xmlst);
            my $vdret = &xmltime2vdr($xmlet);
            if ($vdret < $pivotTime)
            {
                next;
            }
            if ( ( $chanCur ne "" ) && ( $chanCur ne $chan ) )
            {
                $atLeastOneEpg = 1;
                EpgSend ($chanId{$chanCur}, $chanName{$chanCur}, $epgText, $nbEventSent);
                $epgText = "";
                $nbEventSent = 0;
            }
            $chanCur = $chan;
            $nbEventSent++;
            $chanevent = 1;
            my $vdrdur = $vdret - $vdrst;
            my $vdrid = $vdrst / 60 % 0xFFFF;
            
            # Send VDR Event
            
            $epgText .= "E $vdrid $vdrst $vdrdur 0\r\n";
        }
        
        if ( $chanevent == 0 )
        {
            next;
        }
        
        # XML Program Title
        $epgText .= "T $1\r\n" if ( $xmlline =~ m:\<title.*?\>(.*?)\</title\>:o );
        
        # XML Program Sub Title
        $epgText .= "S $1\r\n" if ( $xmlline =~ m:\<sub-title.*?\>(.*?)\</sub-title\>:o );
        
        # XML Program description at required verbosity
        
        if ( ( $founddesc == 0 ) && ( $xmlline =~ m/\<desc.*?\>(.*?)\</o ) )
        {
            if ( $descv == $dc )
            {
                # Send VDR Description & end of event
                $epgText .= "D $1\r\n";
                $epgText .= "e\r\n";
                
                $dc++;
                $founddesc=1;
            }
            else
            {
                # Description is not required verbosity
                $dc++;
            }
        }
        
        # No Description found at required verbosity
        
        if ( ($xmlline =~ /\<\/programme/o ) )
        {
            if ( $founddesc == 0 )
            { 
                $epgText .= "D Info Not Available\r\n";
                $epgText .= "e\r\n";
            }
            $chanevent=0 ;
            $dc=0 ;
            $founddesc=0 ;
        }
    }
    
    if ( $atLeastOneEpg )
    {
        EpgSend ($chanId{$chanCur}, $chanName{$chanCur}, $epgText, $nbEventSent);
    }
}

#---------------------------------------------------------------------------
# main

use Socket;

my $Usage = qq{
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

die $Usage if (!getopts('a:d:p:l:t:x:c:vhs') || $opt_h);

$verbose = 1 if $opt_v;
$sim = 1 if $opt_s;
$adjust = $opt_a || 0;
my $Dest   = $opt_d || "localhost";
my $Port   = $opt_p || 2001;
my $descv   = $opt_l || 0;
my $Timeout = $opt_t || 300; # max. seconds to wait for response
my $xmltvfile = $opt_x  || die "$Usage Need to specify an XMLTV file";
my $channelsfile = $opt_c  || die "$Usage Need to specify a channels.conf file";

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
    
    my $iaddr = inet_aton($Dest)                   || die("no host: $Dest");
    my $paddr = sockaddr_in($Port, $iaddr);
    
    my $proto = getprotobyname('tcp');
    socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die("socket: $!");
    connect(SOCK, $paddr)                       || die("connect: $!");
    select((select(SOCK), $| = 1)[0]);
}

# Look for initial banner
SVDRPreceive(220);
SVDRPsend("CLRE");
SVDRPreceive(250);

# Do the EPG stuff
ProcessEpg();

# Lets get out of here! :-)

SVDRPsend("QUIT");
SVDRPreceive(221);

close(SOCK);
