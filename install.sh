#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
app_dir="$HOME/Library/Application Support/TrueToneHold"
log_dir="$HOME/Library/Logs/TrueToneHold"
plist="$HOME/Library/LaunchAgents/local.truetone-hold.plist"
label="local.truetone-hold"
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'This helper requires macOS.' >&2
    exit 1
fi
if pgrep -x truetone-hold >/dev/null && ! launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    echo 'Another installation is running. Disable it before installing this version.' >&2
    exit 1
fi
xcrun --find clang >/dev/null
mkdir -p "$app_dir" "$log_dir" "$(dirname "$plist")"
build_file="$(mktemp "$app_dir/.build.XXXXXX")"
trap 'rm -f "$build_file"' EXIT
xcrun clang -O2 -fobjc-arc -framework Foundation -framework CoreGraphics -framework IOKit \
    "$repo_dir/src/truetone-hold.m" -o "$build_file"
if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$label"
fi
mv "$build_file" "$app_dir/truetone-hold"
cp "$repo_dir/src/truetone-hold.m" "$app_dir/truetone-hold.m"
# plutil handles quoting and escaping for paths containing spaces or XML characters.
plutil -create xml1 "$plist"
plutil -insert Label -string "$label" "$plist"
plutil -insert ProgramArguments -array "$plist"
plutil -insert ProgramArguments.0 -string "$app_dir/truetone-hold" "$plist"
plutil -insert RunAtLoad -bool YES "$plist"
plutil -insert KeepAlive -dictionary "$plist"
plutil -insert KeepAlive.SuccessfulExit -bool NO "$plist"
plutil -insert ThrottleInterval -integer 10 "$plist"
plutil -insert ProcessType -string Background "$plist"
plutil -insert LimitLoadToSessionType -string Aqua "$plist"
plutil -insert StandardOutPath -string "$log_dir/agent.log" "$plist"
plutil -insert StandardErrorPath -string "$log_dir/agent.log" "$plist"
plutil -lint "$plist"
launchctl bootstrap "gui/$(id -u)" "$plist"
echo 'Installed. Keep the lid open for at least three seconds to capture a reading.'
