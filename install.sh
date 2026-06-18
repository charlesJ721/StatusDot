#!/bin/bash
# StatusDot v3 — one-command install (clean-slate architecture)
# StatusDot reads agent state directly from ~/.hermes/agent_status/
# No bridge script needed. Idle detection is a separate launchd process.
set -e

echo "=== StatusDot v3 ==="
echo ""

# ── Build ──
echo "Building..."
swiftc -O StatusDot.swift -o StatusDot
echo "[OK] Build"

# ── Create .app bundle ──
APP_DIR="$HOME/Applications/StatusDot.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp StatusDot "$APP_DIR/Contents/MacOS/StatusDot"
chmod 755 "$APP_DIR/Contents/MacOS/StatusDot"
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StatusDot</string>
<key>CFBundleIdentifier</key><string>com.arslonga.statusdot</string>
<key>CFBundleName</key><string>StatusDot</string>
<key>CFBundleVersion</key><string>3.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "[OK] App bundle"

# ── Agent status directory ──
mkdir -p "$HOME/.hermes/agent_status"
touch "$HOME/.hermes/agent_status/hermes"
echo "[OK] agent_status dir"

# ── Hermes plugin ──
mkdir -p "$HOME/.hermes/plugins/statusdot"
cp hermes-plugin/plugin.yaml "$HOME/.hermes/plugins/statusdot/"
cp hermes-plugin/__init__.py "$HOME/.hermes/plugins/statusdot/"
echo "[OK] Hermes plugin"

# ── Idle watcher ──
cp status_idle_watch.py "$HOME/.hermes/scripts/"
echo "[OK] Idle watcher"

# ── LaunchAgents ──
# Idle watcher
cat > "$HOME/Library/LaunchAgents/com.arslonga.statusidle.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.arslonga.statusidle</string>
<key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>$HOME/.hermes/scripts/status_idle_watch.py</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
</dict></plist>
PLISTEOF
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.arslonga.statusidle.plist" 2>/dev/null || true
echo "[OK] Idle watcher LaunchAgent"

# StatusDot app
cat > "$HOME/Library/LaunchAgents/com.arslonga.statusdot.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.arslonga.statusdot</string>
<key>ProgramArguments</key><array><string>$APP_DIR/Contents/MacOS/StatusDot</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
</dict></plist>
PLISTEOF
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.arslonga.statusdot.plist" 2>/dev/null || true
echo "[OK] StatusDot LaunchAgent"

echo ""
echo "=== Done! ==="
echo "Menu bar should show a small dot now."
echo "Plugin activates on next Hermes /new or restart."
echo ""
echo "States: idle(gray) · thinking(yellow pulse) · working(yellow) · waiting(yellow pulse) · success(green) · error(red)"
