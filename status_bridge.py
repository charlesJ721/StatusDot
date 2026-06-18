#!/usr/bin/env python3
"""Status Bridge v4 — high-frequency Hermes state inference from state.db.

Polls every 0.2s, reads the last 5 messages to detect:
  idle     — last message is final assistant reply
  thinking — last message is user, no assistant response yet
  working  — tool calls active or tool results being processed
  waiting  — Hermes is waiting for user input (clarify/stuck)

Replaces the slow 0.5s DB bridge. Written as a SystemExtension-style
daemon — no core Hermes modification needed.
"""
import os, time, sqlite3, json

STATUS_FILE  = os.path.expanduser("~/.hermes/agent_status")
STATE_DB     = os.path.expanduser("~/.hermes/state.db")
PREVIEW_LOCK = "/tmp/hermes_preview_active"
PLUGIN_FLAG = os.path.expanduser("~/.hermes/.statusdot_plugin")
TS_FILE     = os.path.expanduser("~/.hermes/.statusdot_ts")
LOG_FILE     = os.path.expanduser("~/.hermes/status_bridge.log")
POLL = 0.2
MAX_MSGS = 8


def log(msg: str) -> None:
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{int(time.time()*1000)} {msg}\n")
    except Exception:
        pass


def infer_state() -> str:
    """Find the most recent user message, then check what follows it."""
    if not os.path.exists(STATE_DB):
        return "idle", False
    try:
        conn = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True)
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT id FROM messages WHERE role='user' AND active=1 "
                "ORDER BY id DESC LIMIT 1"
            )
            row = cur.fetchone()
            if not row:
                conn.close(); return "idle", False
            user_id = row[0]

            # Get all messages after that user message
            cur.execute(
                "SELECT role, tool_calls, content FROM messages "
                "WHERE id > ? AND active=1 ORDER BY id ASC",
                (user_id,)
            )
            after = cur.fetchall()
        finally:
            conn.close()

        if not after:
            return "thinking", False  # user sent, nothing after → thinking

        # Scan from oldest to newest after user message
        has_tool_activity = False
        last_role = None
        last_has_tools = False
        last_content = ""

        for role, raw_tc, content in after:
            last_role = role
            last_content = (content or "")
            last_has_tools = _has_real_tools(raw_tc)
            if role in ("assistant", "tool"):
                has_tool_activity = True

        # ── Decision ──
        # Tool activity in progress but no final answer yet
        if has_tool_activity and last_role != "assistant":
            return "working", True
        if has_tool_activity and last_role == "assistant" and last_has_tools:
            return "working", True

        # Final assistant reply exists → check if waiting, else idle
        if last_role == "assistant" and not last_has_tools:
            low = last_content.lower()[:300]
            if any(w in low for w in [
                "would you like", "do you want", "should i",
                "confirm", "approve", "proceed", "choose",
                "option", "pick one", "which", "prefer",
                "需要确认", "是否", "要不要"
            ]):
                return "waiting", False
            return "idle", False

        return "thinking", False

    except Exception:
        return "idle", False


def _has_real_tools(raw_tools) -> bool:
    """Parse tool_calls, return True if non-empty array."""
    if not raw_tools:
        return False
    try:
        parsed = json.loads(raw_tools)
        return isinstance(parsed, list) and len(parsed) > 0
    except (json.JSONDecodeError, TypeError):
        return False


def atomic_write(path: str, content: str) -> bool:
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


def main():
    log("bridge_v4_start")
    waited = 0
    while not os.path.exists(STATUS_FILE):
        if waited >= 60:
            log("startup_timeout"); return
        time.sleep(1); waited += 1

    last_state = ""
    working_first_seen = 0.0
    WORKING_MIN_SHOW = 1.5  # keep "working" visible for at least 1.5s

    while True:
        # Plugin active → bridge does IDLE detection only
        if os.path.exists(PLUGIN_FLAG):
            if os.path.exists(PREVIEW_LOCK):
                time.sleep(POLL)
                continue
            # Read plugin's last activity timestamp
            try:
                with open(TS_FILE) as f:
                    last_ts = float(f.read().strip())
                idle = (time.time() - last_ts > 0.5)
            except Exception:
                idle = False
            if idle:
                try:
                    current = ""
                    if os.path.exists(STATUS_FILE):
                        with open(STATUS_FILE) as f:
                            current = f.read().strip()
                    if current != "idle":
                        atomic_write(STATUS_FILE, "idle")
                except Exception:
                    pass
            time.sleep(POLL)
            continue

        raw_state, was_working = infer_state()
        now = time.time()

        # If we detected tool activity (was_working=True) but the DB
        # already moved to idle, hold "working" for minimum visibility
        if was_working:
            working_first_seen = now
        elif raw_state != "working" and working_first_seen > 0:
            if now - working_first_seen < WORKING_MIN_SHOW:
                raw_state = "working"
            else:
                working_first_seen = 0

        if raw_state != last_state:
            if atomic_write(STATUS_FILE, raw_state):
                if raw_state == "working":
                    pass  # don't spam log
                else:
                    log(f"state {last_state}->{raw_state}")
                last_state = raw_state
        time.sleep(POLL)


if __name__ == "__main__":
    main()
