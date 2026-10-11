import os, time


def write_atomic(d, name, text):
    tmp = os.path.join(d, name + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, os.path.join(d, name))


def pending(d):
    return sorted(f for f in os.listdir(d) if f.endswith(".csv"))


def cleanup_tmp(d, max_age_s=3600):
    """Remove .tmp orfaos (restos de crash) mais velhos que max_age_s."""
    now = time.time()
    for f in os.listdir(d):
        p = os.path.join(d, f)
        if f.endswith(".tmp") and now - os.path.getmtime(p) > max_age_s:
            os.remove(p)
