#!/bin/sh

echo "Grabbing XMLTV listings!"

tv_grab_uk > freeview.xml

echo "Feeding into VDR via SVDRP"

./xmltv2vdr.pl -l 0 -x freeview.xml -c channels.conf.terr
