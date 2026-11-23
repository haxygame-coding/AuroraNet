#!/bin/sh

export PATH=$PATH:/usr/local/bin

# check if auroranet is installed
NB_BIN=$(which auroranet)
if [ -z "$NB_BIN" ]
then
  exit 0
fi
# start auroranet daemon service
echo "auroranet daemon service still running. You can uninstall it by running: "
echo "sudo auroranet service stop"
echo "sudo auroranet service uninstall"
