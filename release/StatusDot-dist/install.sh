#!/bin/bash
set -e
echo "=== StatusDot ==="
echo "Pick agent: 1)Hermes 2)Claude 3)Codex 4)OpenClaw 5)Manual"
read -p "Choice [1]: " C
case "${C:-1}" in 1) A="hermes";; 2) A="claude";; 3) A="codex";; 4) A="openclaw";; 5) A="manual";; *) A="hermes";; esac
mkdir -p "$HOME/.hermes/scripts"
echo "$A" > "$HOME/.hermes/status_provider"
touch "$HOME/.hermes/agent_status"
APP="$HOME/Applications/StatusDot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(dirname "$0")/StatusDot" "$APP/Contents/MacOS/"
chmod 755 "$APP/Contents/MacOS/StatusDot"
cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StatusDot</string>
<key>CFBundleIdentifier</key><string>com.arslonga.statusdot</string>
<key>CFBundleName</key><string>StatusDot</string>
<key>CFBundleVersion</key><string>2.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
PL="$HOME/Library/LaunchAgents/com.arslonga.statusdot.plist"
cat > "$PL" << PL2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.arslonga.statusdot</string>
<key>ProgramArguments</key><array><string>$APP/Contents/MacOS/StatusDot</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
PL2
launchctl bootout gui/$(id -u)/com.arslonga.statusdot 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PL"
if [ "$A" = "hermes" ]; then
    cp "$(dirname "$0")/status_bridge.py" "$HOME/.hermes/scripts/"
    BP="$HOME/Library/LaunchAgents/com.arslonga.statusbridge.plist"
    cat > "$BP" << BR
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.arslonga.statusbridge</string>
<key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>$HOME/.hermes/scripts/status_bridge.py</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
BR
    launchctl bootstrap gui/$(id -u) "$BP" 2>/dev/null || true
fi
echo "Done! StatusDot in menu bar."
