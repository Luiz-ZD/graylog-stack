import hashlib, json, os, subprocess


class UploadError(Exception):
    pass


def _md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


class Uploader:
    def __init__(self, cfg):
        self.cfg = cfg

    def _remote(self, name):
        return f"{self.cfg.remote}:{self.cfg.bucket}/{self.cfg.prefix}{name}"

    def _run(self, *args):
        p = subprocess.run(["rclone", "--config", self.cfg.rclone_conf, "--retries", "3", "--low-level-retries", "5", *args],
                           capture_output=True, text=True, timeout=300)
        if p.returncode:
            raise UploadError(f"rclone {args[0]} rc={p.returncode}: {p.stderr.strip()[:300]}")
        return p.stdout

    def send(self, path):
        name = os.path.basename(path)
        local_md5, size = _md5(path), os.path.getsize(path)
        self._run("copyto", path, self._remote(name))
        info = json.loads(self._run("lsjson", "--hash", self._remote(name)) or "[]")
        if not info:
            raise UploadError("objeto nao encontrado apos envio")
        rsize = info[0]["Size"]
        rmd5 = (info[0].get("Hashes") or {}).get("md5")
        if rsize != size or (rmd5 is not None and rmd5 != local_md5):
            raise UploadError(f"verificacao falhou: local={size}/{local_md5} remoto={rsize}/{rmd5}")
        return {"name": name, "bytes": size, "md5": local_md5, "remote_size": rsize, "remote_md5": rmd5, "ok": True}
