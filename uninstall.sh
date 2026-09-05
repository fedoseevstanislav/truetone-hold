#!/bin/bash
set -euo pipefail
label="local.truetone-hold"
if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$label"
fi
rm -f "$HOME/Library/LaunchAgents/$label.plist"
echo 'Login helper disabled. Program files and logs remain in Library for inspection.'
