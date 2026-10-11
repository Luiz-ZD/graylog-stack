import logging, os, sys, time
from datetime import datetime, timezone

from . import config, csvout, ledger, spool, status, window
from .graylog import GraylogClient
from .uploader import Uploader

log = logging.getLogger("export")
U = timezone.utc
Z = "%Y-%m-%dT%H:%M:%SZ"


def _upload_pending(cfg, up, now, max_fail=2):
    """Envia o spool do mais antigo ao mais novo. Um arquivo que falha nao bloqueia os demais, mas
    apos max_fail falhas no ciclo para (bucket fora do ar nao custa uma tentativa por arquivo)."""
    errs = []
    for name in spool.pending(cfg.spool_dir):
        path = os.path.join(cfg.spool_dir, name)
        try:
            r = up.send(path)
        except Exception as e:
            errs.append(f"{name}: {e}")
            log.error("envio falhou %s", errs[-1])
            if len(errs) >= max_fail:
                break
            continue
        ledger.append(cfg.state_dir, {"ts": now.strftime(Z), "event": "uploaded", **r})
        os.remove(path)
        log.info("enviado %s (%d bytes)", name, r["bytes"])
    return "; ".join(errs) or None


def run_once(cfg, now, client, up):
    if not cfg.enabled:
        status.write(cfg.state_dir, enabled=False, last_tick=int(now.timestamp()))
        return {"windows": 0}
    cp_path = os.path.join(cfg.state_dir, "checkpoint")
    start, why = window.load_checkpoint(cp_path, now, cfg.lag_min, cfg.max_catchup_min)
    if why:
        log.warning(why)
        ledger.append(cfg.state_dir, {"ts": now.strftime(Z), "event": "checkpoint_reset", "why": why})
        window.save_checkpoint(cp_path, start)
    n, err = 0, None
    gap = None
    if why and "antigo" in why:
        gap = {"ts": now.strftime(Z), "why": why}
    bl = client.backlog() if hasattr(client, "backlog") else None
    deferred = bl is not None and bl > cfg.journal_max_backlog
    if deferred:
        err = f"graylog atrasado: {bl} entradas no journal (> {cfg.journal_max_backlog}); janelas adiadas"
        log.warning(err)
    for a, b in ([] if deferred else window.closed_windows(start, now, cfg.lag_min)):
        try:
            rows = client.fetch(a, b)
        except Exception as e:
            err = f"graylog: {e}"
            log.error(err)
            break
        if rows:
            name = window.filename(b, cfg.tz)
            spool.write_atomic(cfg.spool_dir, name, csvout.render(rows))
            ledger.append(cfg.state_dir, {"ts": now.strftime(Z), "event": "exported", "window_start": a.strftime(Z),
                                          "window_end": b.strftime(Z), "name": name, "events": len(rows)})
        window.save_checkpoint(cp_path, b)
        n += 1
    spool.cleanup_tmp(cfg.spool_dir)
    uerr = _upload_pending(cfg, up, now)
    pend = spool.pending(cfg.spool_dir)
    oldest = min((os.path.getmtime(os.path.join(cfg.spool_dir, p)) for p in pend), default=None)
    cur = window.load_checkpoint(cp_path, now, cfg.lag_min, cfg.max_catchup_min)[0]
    status.write(cfg.state_dir, enabled=True, last_tick=int(now.timestamp()), spool_count=len(pend),
                 oldest_spool_age_s=None if oldest is None else int(now.timestamp() - oldest),
                 checkpoint=cur.strftime(Z), last_error=err or uerr,
                 **({"last_ok": int(now.timestamp())} if not (err or uerr) else {}), **({"last_gap": gap} if gap else {}))
    return {"windows": n, "error": err or uerr}


def loop(cfg):
    client, up = GraylogClient(cfg), Uploader(cfg)
    os.makedirs(cfg.state_dir, exist_ok=True)
    os.makedirs(cfg.spool_dir, exist_ok=True)
    while True:
        try:
            run_once(cfg, datetime.now(U), client, up)
        except Exception as e:
            log.exception("ciclo falhou: %s", e)
        time.sleep(60 - (time.time() % 60) + 5)  # proximo minuto + 5 s


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
    loop(config.load())
