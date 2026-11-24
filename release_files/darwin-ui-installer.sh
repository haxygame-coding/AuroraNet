#!/bin/sh

export PATH=$PATH:/usr/local/bin:/opt/homebrew/bin

# check if the AuroraNet client is installed
NB_BIN=$(which auroranet)
if [ -n "$NB_BIN" ]
then
  echo "Stopping and uninstalling AuroraNet daemon"
  auroranet service stop || true
  auroranet service uninstall || true
fi

# check if the AuroraNet client is installed
NB_BIN=$(which auroranet)
if [ -z "$NB_BIN" ]
then
  echo "AuroraNet daemon is not installed. Please run: brew install haxygame-coding/tap/auroranet"
  exit 1
fi
NB_UI_VERSION=$1
NB_VERSION=$(auroranet version)
if [ "X-$NB_UI_VERSION" != "X-$NB_VERSION" ]
then
  echo "AuroraNet's daemon is running with a different version than the AuroraNet UI:"
  echo "AuroraNet UI Version: $NB_UI_VERSION"
  echo "AuroraNet Daemon Version: $NB_VERSION"
  echo "Please run: brew install haxygame-coding/tap/auroranet"
  echo "to update it"
fi

if [ -n "$NB_BIN" ]
then
  echo "Stopping AuroraNet daemon"
  osascript -e 'quit app "AuroraNet"' 2> /dev/null || true
  auroranet service stop 2> /dev/null || true
fi

# start the AuroraNet daemon service
echo "Starting AuroraNet daemon"
auroranet service install 2> /dev/null || true
auroranet service start || true

# start app
open /Applications/AuroraNet.app
