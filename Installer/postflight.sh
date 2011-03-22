#!/bin/sh

killall GPGServices
killall -9 GPGServices
./ServicesRestart
sleep 3
sudo ./ServicesRestart

exit 0
