"""StatusDot v3 — multi-agent state via lifecycle hooks.

Writes thinking/working/waiting to ~/.hermes/agent_status/hermes.
Idle detection is handled by status_idle_watch.py (separate process).
"""

import os


STATUS_DIR = os.path.expanduser("~/.hermes/agent_status")
STATUS_FILE = os.path.join(STATUS_DIR, "hermes")


def _write(state: str) -> None:
    """Atomic write: tmp file in same dir → fsync → rename."""
    tmp = STATUS_FILE + ".tmp"
    try:
        with open(tmp, "w") as f:
            f.write(state)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp, STATUS_FILE)
    except Exception:
        pass


def _touch(**kwargs) -> None:
    """Update mtime without changing content (post_llm_call)."""
    try:
        os.utime(STATUS_FILE, None)
    except FileNotFoundError:
        pass


def _on_thinking(**kwargs):
    _write("thinking")


def _on_working(**kwargs):
    _write("working")


def _on_waiting(**kwargs):
    _write("waiting")


def _on_post_approval(**kwargs):
    _write("thinking")


def register(ctx):
    ctx.register_hook("pre_llm_call", _on_thinking)
    ctx.register_hook("pre_tool_call", _on_working)
    ctx.register_hook("post_tool_call", _on_thinking)
    ctx.register_hook("post_llm_call", _touch)
    ctx.register_hook("pre_approval_request", _on_waiting)
    ctx.register_hook("post_approval_response", _on_post_approval)
