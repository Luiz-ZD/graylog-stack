import os
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

U = timezone.utc


def floor_minute(dt):
    return dt.replace(second=0, microsecond=0)


def closed_windows(checkpoint, now, lag_min):
    limit = floor_minute(now) - timedelta(minutes=lag_min)
    w = checkpoint
    while w + timedelta(minutes=1) <= limit:
        yield (w, w + timedelta(minutes=1))
        w += timedelta(minutes=1)


def lucene_ts(dt):
    return dt.astimezone(U).strftime("%Y-%m-%d %H:%M:%S.000")


def filename(end_utc, tz):
    return end_utc.astimezone(ZoneInfo(tz)).strftime("levels_0_a_3_%Y%m%d_%H%M%S.csv")


def save_checkpoint(path, dt):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(dt.astimezone(U).strftime("%Y-%m-%dT%H:%M:%SZ"))
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)


def load_checkpoint(path, now, lag_min, max_catchup_min):
    fresh = floor_minute(now) - timedelta(minutes=lag_min)
    try:
        with open(path) as f:
            raw = f.read().strip()
        cp = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=U)
    except FileNotFoundError:
        return fresh, "sem checkpoint: iniciando agora, sem backfill"
    except (ValueError, OverflowError):
        return fresh, "checkpoint invalido: iniciando agora, sem backfill"
    if cp > fresh + timedelta(minutes=1):
        return fresh, f"checkpoint no futuro ({cp:%Y-%m-%dT%H:%MZ}): relogio voltou ou arquivo editado; reiniciando agora"
    oldest = fresh - timedelta(minutes=max_catchup_min)
    if cp < oldest:
        return oldest, f"checkpoint muito antigo ({cp:%Y-%m-%dT%H:%MZ}): recuperando apenas {max_catchup_min} min"
    return cp, None
