# StatusDot

macOS menu bar traffic light that shows your AI agent's real-time state.

Supports **Hermes**, **Claude Code**, **Codex CLI**, and **OpenClaw** — or any agent that can write to a file.

<img width="300" alt="StatusDot in menu bar" src="https://img.shields.io/badge/macOS-13%2B-blue">

## States

| State | Visual |
|-------|--------|
| idle | Three dim dots — agent is waiting |
| thinking | Three breathing dots (R·Y·G) — agent is processing |
| working | Chase wave across dots — executing tools |
| success | Pendulum ripple → all green — task complete |
| error | Fast flash → all red — something went wrong |
| waiting | Three breathing yellow — waiting for input |

## Install

```bash
# 1. Download and unzip
unzip StatusDot.zip && cd StatusDot-dist

# 2. Run installer (picks your agent)
bash install.sh

# 3. Done — StatusDot appears in your menu bar
```

For Claude Code / Codex / OpenClaw, the installer prints hook configuration to paste into your agent's settings file.

Switch agents anytime: click StatusDot → **Switch Agent**.

## Architecture

```
Agent hooks → ~/.hermes/agent_status → StatusDot reads → menu bar display
                    ↑
          Hermes: status_bridge.py polls state.db
          Others: native hooks write directly
```

One file, one reader, one writer. No polling overhead for non-Hermes agents.

## Build from Source

```bash
swiftc -o StatusDot StatusDot.swift
```

Requires macOS 13+ and Xcode Command Line Tools.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.arslonga.statusdot
launchctl bootout gui/$(id -u)/com.arslonga.statusbridge 2>/dev/null
rm -rf ~/Applications/StatusDot.app
rm ~/Library/LaunchAgents/com.arslonga.status*.plist
rm -rf ~/.hermes/scripts/status_bridge.py
```

## License

MIT
