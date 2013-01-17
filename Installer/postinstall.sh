#!/bin/bash
# This is a package post-install script for GPGServices.


# config #######################################################################
sysdir="/Library/Services"
homedir="$HOME/Library/Services"
bundle="GPGServices.service"
USER=${USER:-$(id -un)}
################################################################################


# Find real target #############################################################
dir="$PWD"
cd "$(readlink "$2")"
target="$(pwd -P)"

if cd "$homedir" && [[ "$target" == "$(pwd -P)" ]] ;then
	target="$homedir"
else
	target="$sysdir"
fi
################################################################################


# Check if GPGServices is correct installed ####################################
if [[ ! -e "$target/$bundle" ]] ;then
	echo "[gpgservices] Can't find '$bundle'.  Aborting." >&2
	exit 1
fi
################################################################################


# Quit GPGServices #############################################################
if ps -axo command | grep -q "[G]PGServices" ;then
	killall GPGServices
fi
################################################################################


# Cleanup ######################################################################
echo "[gpgservices] Removing duplicates of the bundle..."
[[ "$target" != "$sysdir" ]] && rm -rf "$sysdir/$bundle"
[[ "$target" != "$homedir" ]] && rm -rf "$homedir/$bundle"
################################################################################


# Permissions ##################################################################
echo "[gpgservices] Fixing permissions..."
if [ "$target" == "$homedir" ]; then
    chown -R "$USER:staff" "$homedir/$bundle"
fi
chmod -R 755 "$target"
################################################################################


# Reload keyboard preferences ##################################################
"$target/GPGServices.service/Contents/Resources/ServicesRestart"
################################################################################

exit 0
