#!/usr/bin/env python3
"""Status Bridge v3 — writes Hermes Agent state to ~/.hermes/agent_status.

Only active when agent is "hermes". For Claude Code / Codex / OpenClaw,
the agent's native hooks write directly to the file — no bridge needed.

States: idle | thinking | working
"""
import os, time, sqlite3, json, fcntl

STATUS_FILE  = os.path.expanduser("~/.hermes/agent_status")
PROVIDER_CFG = os.path.expanduser("~/.hermes/status_provider")
# Check both lock locations for backward compat with compiled binary
PREVIEW_LOCKS = [
    "/tmp/hermes_preview_active",                       # compiled StatusDot binary
    os.path.expanduser("~/.hermes/.preview_lock"),      # future versions
]
STATE_DB     = os.path.expanduser("~/.hermes/state.db")
LOG_FILE     = os.path.expanduser("~/.hermes/status_bridge.log")
POLL = 0.5
STARTUP_TIMEOUT = 30  # max seconds waiting for STATUS_FILE


def log(msg: str) -> None:
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{int(time.time())} {msg}\n")
    except Exception:
        pass


def get_provider() -> str:
    try:
        with open(PROVIDER_CFG) as f:
            raw = f.read().strip().lower()
        # Whitelist validation
        if raw in ("hermes", "claude", "codex", "openclaw", "manual"):
            return raw
        return "hermes"
    except Exception:
        return "hermes"


def infer_hermes_state() -> str:
    """Infer state from Hermes state.db message tail (read-only)."""
    if not os.path.exists(STATE_DB):
        return "idle"
    try:
        # Read-only URI to avoid lock contention with Hermes
        conn = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True)
        try:
            cur = conn.cursor()
            cur.execute("SELECT session_id FROM messages ORDER BY id DESC LIMIT 1")
            row = cur.fetchone()
            if not row:
                return "idle"
            sid = row[0]
            # Only need the most recent message (LIMIT 1, not 3)
            cur.execute(
                "SELECT role, tool_calls FROM messages "
                "WHERE session_id=? AND active=1 ORDER BY id DESC LIMIT 1",
                (sid,)
            )
            msg = cur.fetchone()
        finally:
            conn.close()

        if not msg:
            return "idle"

        role = msg[0]
        raw_tools = msg[1]

        # Parse tool_calls as JSON to avoid bool() trap on '[]'
        has_tools = False
        if raw_tools:
            try:
                parsed = json.loads(raw_tools)
                has_tools = isinstance(parsed, list) and len(parsed) > 0
            except (json.JSONDecodeError, TypeError):
                has_tools = bool(raw_tools)  # fallback for non-JSON

        if role == "user":
            return "thinking"
        if role == "tool":
            return "working"
        if role == "assistant":
            return "working" if has_tools else "idle"
        return "idle"
    except Exception:
        return "idle"


def atomic_write(path: str, content: str) -> bool:
    """Write to .tmp then rename — crash-safe, no partial reads."""
    tmp = path + ".tmp"
    try:
        with open(tmp, "w") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp, path)
        return True
    except Exception:
        return False


def write_status(state: str) -> None:
    # Check preview locks
    for lock in PREVIEW_LOCKS:
        if os.path.exists(lock):
            return
    try:
        current = ""
        if os.path.exists(STATUS_FILE):
            with open(STATUS_FILE) as f:
                current = f.read().strip()
        if current != state:
            if not atomic_write(STATUS_FILE, state):
                log(f"write_failed state={state}")
    except Exception:
        log(f"write_error state={state}")


def main():
    log("bridge_start")
    waited = 0
    while not os.path.exists(STATUS_FILE):
        if waited >= STARTUP_TIMEOUT:
            log("startup_timeout")
            return
        time.sleep(1)
        waited += 1

    log("bridge_ready")
    last_provider = ""
    while True:
        provider = get_provider()
        if provider == "hermes":
            state = infer_hermes_state()
            write_status(state)
        # For non-Hermes: do nothing — hooks write directly
        if provider != last_provider:
            log(f"provider_switch {last_provider}->{provider}")
            last_provider = provider
        time.sleep(POLL)


if __name__ == "__main__":
    main()
