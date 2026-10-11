import json, os, time


def write(state_dir, **fields):
    p = os.path.join(state_dir, "status.json")
    cur = {}
    try:
        with open(p) as f:
            cur = json.load(f)
    except Exception:
        pass
    cur.update(fields)
    cur["updated_at"] = int(time.time())
    with open(p + ".tmp", "w") as f:
        json.dump(cur, f)
    os.replace(p + ".tmp", p)
