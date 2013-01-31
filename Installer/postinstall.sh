#!/bin/bash
# This is a package post-install script for GPGServices.


# config #######################################################################
sysdir="/Library/Services"
homedir="$HOME/Library/Services"
bundle="GPGServices.service"
USER=${USER:-$(id -un)} 
temporarydir="$2"
################################################################################


# Find real target #############################################################
existingInstallationAt=""

if [[ -e "$homedir/$bundle" ]]; then
	existingInstallationAt="$homedir"
	target="$homedir"
elif [[ -e "$sysdir/$bundle" ]]; then
	existingInstallationAt="$sysdir"
	target="$sysdir"
else
	target="$sysdir"
fi

################################################################################

echo "Temporary dir: $temporarydir"
echo "existing installation at: $existingInstallationAt"
echo "installation target: $target"

# Check if GPGServices is correct installed in the temporary directory.
if [[ ! -e "$temporarydir/$bundle" ]] ;then
	echo "[gpgservices] Couldn't install '$bundle' in temporary directory $temporarydir.  Aborting." >&2
	exit 1
fi
################################################################################

# Quit GPGServices #############################################################
if ps -axo command | grep -q "[G]PGServices" ;then
	killall GPGServices
fi
################################################################################


# Cleanup ######################################################################
if [[ "$existingInstallationAt" != "" ]]; then
	echo "[gpgservices] Removing existing installation of the bundle..."
	rm -rf "$existingInstallationAt/$bundle" || exit 1
fi
################################################################################

# Proper installation ##########################################################
echo "[gpgservices] Moving bundle to final destination: $target"
if [[ ! -d "$target" ]]; then
	mkdir -p "$target" || exit 1
fi
mv "$temporarydir/$bundle" "$target/"
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
