#!/bin/bash
# StatusDot — one-command build & install
set -e

echo "=== StatusDot ==="
echo ""

# ── Build ──
echo "Building..."
swiftc -o StatusDot StatusDot.swift
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
<key>CFBundleVersion</key><string>2.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "[OK] App bundle"

# ── Pick agent ──
echo ""
echo "Which AI agent?"
echo "  1) Hermes      2) Claude Code"
echo "  3) Codex CLI   4) OpenClaw"
echo "  5) Manual"
read -p "Choice [1]: " C
case "${C:-1}" in
  1) AGENT="hermes" ;;  2) AGENT="claude" ;;
  3) AGENT="codex" ;;   4) AGENT="openclaw" ;;
  5) AGENT="manual" ;;  *) AGENT="hermes" ;;
esac
echo "-> $AGENT"

mkdir -p "$HOME/.hermes/scripts"
echo "$AGENT" > "$HOME/.hermes/status_provider"
touch "$HOME/.hermes/agent_status"

# ── Install bridge (Hermes only) ──
if [ "$AGENT" = "hermes" ]; then
    cp status_bridge.py "$HOME/.hermes/scripts/"
    BP="$HOME/Library/LaunchAgents/com.arslonga.statusbridge.plist"
    cat > "$BP" << BRPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.arslonga.statusbridge</string>
<key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>$HOME/.hermes/scripts/status_bridge.py</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
BRPLIST
    launchctl bootstrap gui/$(id -u) "$BP" 2>/dev/null || true
    echo "[OK] Hermes bridge"
fi

# ── Launch StatusDot ──
PLIST="$HOME/Library/LaunchAgents/com.arslonga.statusdot.plist"
BIN="$APP_DIR/Contents/MacOS/StatusDot"
cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.arslonga.statusdot</string>
<key>ProgramArguments</key><array><string>$BIN</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
PLISTEOF
launchctl bootout gui/$(id -u)/com.arslonga.statusdot 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"
echo "[OK] StatusDot running"

# ── Hook help (non-Hermes) ──
case "$AGENT" in
  claude)
    echo ""
    echo "--- Add to ~/.claude/settings.json: ---"
    echo '"UserPromptSubmit" -> [echo thinking > ~/.hermes/agent_status]'
    echo '"PreToolUse"      -> [echo working  > ~/.hermes/agent_status]'
    echo '"Stop"            -> [echo idle     > ~/.hermes/agent_status]'
    ;;
  codex)
    echo "--- Codex: configure PostToolUse hooks to write ~/.hermes/agent_status ---"
    ;;
  openclaw)
    echo "--- OpenClaw: create HOOK.md with message:received/agent:stop events ---"
    ;;
esac

echo ""
echo "=== Done! ==="
echo "Switch agents: click StatusDot -> Switch Agent"
