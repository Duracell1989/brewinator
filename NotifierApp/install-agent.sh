#!/bin/sh
# Registers the resident notifier agent with launchd at cask install time.
#
# This ships inside BrewinatorNotify.zip rather than living in the cask,
# because the cask itself cannot do it: `postflight_steps` run inside a sandbox
# and launchd refuses job submission from any sandboxed process - even
# `sandbox-exec -p '(version 1)(allow default)'` fails with `Bootstrap failed:
# 5: Input/output error` (Homebrew/brew#23891). An `installer script:` runs
# outside that sandbox, which is the whole reason this file exists.
#
# Homebrew runs installer artifacts *before* it moves the app, so the program
# named below does not exist yet when the job is submitted: it lands on exit 78
# (EX_CONFIG) and `KeepAlive` respawns it once the app arrives, roughly a
# launchd throttle interval later. Verified, not assumed.
#
# It never fails the install. A refused bootstrap costs notifications until
# brewinator's own `NotifierAgentActivation` retries on its next run; an
# aborted cask install would cost the app itself.

set -eu

label="dev.b89.brewinator.notifier"
program="${1:-/Applications/BrewinatorNotify.app/Contents/MacOS/BrewinatorNotify}"
plist="$HOME/Library/LaunchAgents/$label.plist"
# The domain target has to name a numeric uid - `gui/ben` is rejected, only
# `gui/501` is accepted - and no cask install-step token expands to one, which
# is why this is a script and not a declarative step.
domain="gui/$(/usr/bin/id -u)"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$program</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
PLIST

# Reinstalling over a loaded agent: `bootstrap` refuses a label already in the
# domain, so unload it first. Best-effort - `bootout` fails when nothing is
# loaded, which is the ordinary first-install case.
/bin/launchctl bootout "$domain/$label" 2>/dev/null || true

if /bin/launchctl bootstrap "$domain" "$plist" 2>/dev/null; then
  echo "Loaded $label."
else
  echo "Could not load $label - brewinator will retry on its next run."
fi
