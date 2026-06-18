import os, time, tempfile

STATUS_DIR = os.path.expanduser("~/.hermes/agent_status")
IDLE_FILE = os.path.join(STATUS_DIR, "__idle__")
LOCK_FILE = "/tmp/hermes_preview_active"
IDLE_THRESHOLD = 1.5

def atomic_write(path, content):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    os.write(fd, content.encode())
    os.fsync(fd)
    os.close(fd)
    os.rename(tmp, path)

def is_idle():
    now = time.time()
    for f in os.listdir(STATUS_DIR):
        fp = os.path.join(STATUS_DIR, f)
        if f.startswith(".") or f == "__idle__" or not os.path.isfile(fp):
            continue
        if now - os.path.getmtime(fp) < IDLE_THRESHOLD:
            return False
    return True

while True:
    if os.path.exists(LOCK_FILE):
        time.sleep(0.5)
        continue
    if is_idle():
        try:
            with open(IDLE_FILE) as f:
                if f.read().strip() == "idle":
                    time.sleep(0.5)
                    continue
        except FileNotFoundError:
            pass
        atomic_write(IDLE_FILE, "idle")
    else:
        if os.path.exists(IDLE_FILE):
            try:
                with open(IDLE_FILE) as f:
                    if f.read().strip() == "idle":
                        os.remove(IDLE_FILE)
            except Exception:
                pass
    time.sleep(0.5)
