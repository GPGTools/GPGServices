#!/bin/bash

# Old version must not run in the background
killall GPGServices
sleep 1
killall -9 GPGServices

# Where to install it
_target="/Library/Services/"
if ( test -e "$HOME/Library/Services/GPGServices.service" ) then
    _target="$HOME/Library/Services/"
    chown -R $USER "$_target"
fi

# Remove (old) versions
rm -rf $HOME/Library/Services/GPGServices.service
rm -rf /Library/Services/GPGServices.service

# Install it
mkdir -p "$_target"
mv /private/tmp/GPGServices.service "$_target"

# Cleanup
if ( test -e "$HOME/Library/Services/GPGServices.service" ) then
    chown -R $USER "$_target"
fi

# Reload keyboard preferences
./ServicesRestart
sleep 2
sudo ./ServicesRestart

exit 0
