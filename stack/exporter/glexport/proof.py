import json, os, subprocess, sys

from . import config


def main(argv):
    n = int(argv[0]) if argv else 10
    cfg = config.load()
    with open(os.path.join(cfg.state_dir, "ledger.jsonl")) as f:
        lines = [json.loads(l) for l in f if '"uploaded"' in l][-n:]
    bad = 0
    for e in lines:
        out = subprocess.run(["rclone", "--config", cfg.rclone_conf, "lsjson", "--hash",
                              f"{cfg.remote}:{cfg.bucket}/{cfg.prefix}{e['name']}"], capture_output=True, text=True)
        info = json.loads(out.stdout or "[]") if out.returncode == 0 else []
        ok = bool(info) and info[0]["Size"] == e["bytes"]
        bad += 0 if ok else 1
        print(("OK   " if ok else "FALTA"), e["ts"], e["name"], e["bytes"], "bytes")
    print(f"{len(lines) - bad}/{len(lines)} conferidos no bucket")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
