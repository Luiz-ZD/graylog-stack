import re
from datetime import datetime, timezone

HEADER = "timestamp,source,level,message"
_INT = re.compile(r"^-?\d+$")


def _q(s):
    return '"' + s.replace('"', '""') + '"'


def row(timestamp, source, level, message):
    lv = level if (level == "" or _INT.match(level)) else _q(level)
    return ",".join([_q(timestamp), _q(source), lv, _q(message)])


def render(rows):
    body = "".join(row(*r) + "\n" for r in rows)
    return (HEADER + "\n" + body) if body else ""


def utc_ts(raw):
    """Normaliza o timestamp do Graylog (pode vir com offset local) para UTC 'YYYY-MM-DDTHH:MM:SS.mmmZ'."""
    s = raw.strip()
    try:
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,6}))?(.*)$", s)
        if not m:
            return raw
        base, frac, tz = m.group(1), (m.group(2) or "0"), (m.group(3) or "+00:00")
        dt = datetime.fromisoformat(f"{base}.{frac.ljust(6, '0')}{tz}").astimezone(timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"
    except ValueError:
        return raw
