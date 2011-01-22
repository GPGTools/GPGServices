#!/bin/bash
#
# This script creates a DMG  for GPGServices
#
# (c) by Felix Co and Alexander Willner
#

# Build the installer
if ( test -e /usr/local/bin/packagesbuild ) then
	echo "Building the installer..."
	/usr/local/bin/packagesbuild GPGServices.pkgproj
else
	echo "ERROR: You need the Application \"Packages\"!"
	echo "get it at http://s.sudre.free.fr/Software/Packages.html"
	exit 1
fi

version=$(date "+%Y%m%d")
version="1.3"
dmg="../build/GPGServices-$version.dmg"

# remove files from earlier execution
rm "$dmg"
rm "$dmg.sig"

tar xfvj template.dmg.tar.bz2

hdiutil attach "template.dmg" -noautoopen -quiet -mountpoint "gpgtools_diskimage"


# Copy the relevant files
ditto --rsrc ../build/GPGServices.mpkg gpgtools_diskimage/Install\ GPGServices.mpkg
ditto --rsrc Uninstall_GPGServices.app gpgtools_diskimage/Uninstall\ GPGServices.app
cp gpgtoolsdmg.icns gpgtools_diskimage/.VolumeIcon.icns
cp dmg_background.png gpgtools_diskimage/.background/dmg_background.png
./setfileicon trash.icns gpgtools_diskimage/Uninstall\ GPGServices.app
./setfileicon installer.icns gpgtools_diskimage/Install\ GPGServices.mpkg

# get the name of the dvice to detatch it
dmg_device=` hdiutil info | grep "gpgtools_diskimage" | awk '{print $1}' `

hdiutil detach $dmg_device -quiet -force

hdiutil convert "template.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$dmg"

# remove the extracted template
rm template.dmg

gpg2 --detach-sign -u 76D78F0500D026C4 "$dmg"
