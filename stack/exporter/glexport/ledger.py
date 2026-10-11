import json, os


def _rotate(path, keep):
    for i in range(keep - 1, 0, -1):
        if os.path.exists(f"{path}.{i}"):
            os.replace(f"{path}.{i}", f"{path}.{i + 1}")
    os.replace(path, f"{path}.1")
    extra = f"{path}.{keep + 1}"
    if os.path.exists(extra):
        os.remove(extra)


def append(state_dir, entry, max_bytes=20 * 1024 * 1024, keep=5):
    path = os.path.join(state_dir, "ledger.jsonl")
    if os.path.exists(path) and os.path.getsize(path) >= max_bytes:
        _rotate(path, keep)
    with open(path, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        f.flush()
        os.fsync(f.fileno())
