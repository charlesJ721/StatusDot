"""StatusDot Hermes plugin — precise state tracking via lifecycle hooks.

Writes thinking/working/waiting states. Idle detection is handled
by status_bridge.py (0.5s inactivity timeout).
"""

import os, time

STATUS_FILE = os.path.expanduser("~/.hermes/agent_status")
TS_FILE     = os.path.expanduser("~/.hermes/.statusdot_ts")
PLUGIN_FLAG = os.path.expanduser("~/.hermes/.statusdot_plugin")


def _write(state: str) -> None:
    """Atomic write state + timestamp."""
    tmp_s = STATUS_FILE + ".tmp"
    tmp_t = TS_FILE + ".tmp"
    try:
        with open(tmp_s, "w") as f:
            f.write(state)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp_s, STATUS_FILE)
        with open(tmp_t, "w") as f:
            f.write(str(time.time()))
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp_t, TS_FILE)
    except Exception:
        pass


def _on_thinking(**kwargs):
    _write("thinking")

def _on_working(**kwargs):
    _write("working")

def _on_waiting(**kwargs):
    _write("waiting")

def _on_post_approval(**kwargs):
    _write("working")


def register(ctx):
    # Signal to bridge: plugin is active
    try:
        with open(PLUGIN_FLAG, "w") as f:
            f.write("1")
    except Exception:
        pass

    ctx.register_hook("pre_llm_call",           _on_thinking)
    ctx.register_hook("pre_tool_call",          _on_working)
    ctx.register_hook("post_tool_call",         _on_thinking)
    ctx.register_hook("pre_approval_request",   _on_waiting)
    ctx.register_hook("post_approval_response", _on_post_approval)
