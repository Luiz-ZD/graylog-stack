import base64, csv, io, json, urllib.request
from datetime import timedelta

from . import csvout, window


class GraylogError(Exception):
    pass


def _lq(s):
    """Escapa o valor para uso entre aspas em Lucene."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def build_query(cfg, start, end):
    rng = 'gl2_receive_timestamp:["%s" TO "%s"}' % (window.lucene_ts(start), window.lucene_ts(end))
    q = f"{rng} AND ({cfg.export_filter})"
    if cfg.exclude_sources:
        q += " AND NOT (" + " OR ".join('source:"%s"' % _lq(s) for s in cfg.exclude_sources) + ")"
    return q


def parse_csv(text):
    rows = list(csv.reader(io.StringIO(text, newline="")))
    if not rows:
        return []
    if [h.strip('"') for h in rows[0]] != ["timestamp", "source", "level", "message"]:
        raise GraylogError(f"cabecalho inesperado: {rows[0]}")
    data = [r for r in rows[1:] if r]
    if any(len(r) != 4 for r in data):
        raise GraylogError("linha com numero de colunas invalido")
    out = [(csvout.utc_ts(r[0]), r[1], r[2], r[3]) for r in data]
    return sorted(out, key=lambda r: r[0], reverse=True)


class GraylogClient:
    def __init__(self, cfg):
        self.cfg = cfg

    def backlog(self):
        """Entradas do journal ainda nao processadas (None se nao for possivel saber)."""
        c = self.cfg
        req = urllib.request.Request(c.graylog_url.rstrip("/") + "/api/system/journal", headers={
            "Authorization": "Basic " + base64.b64encode(f"{c.token}:token".encode()).decode(), "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return int(json.loads(r.read().decode()).get("uncommitted_journal_entries"))
        except Exception:
            return None

    def fetch(self, start, end):
        c = self.cfg
        iso = lambda d: d.strftime("%Y-%m-%dT%H:%M:%S.000Z")
        body = {"query_string": {"type": "elasticsearch", "query_string": build_query(c, start, end)},
                "timerange": {"type": "absolute", "from": iso(start - timedelta(hours=c.slack_hours)),
                              "to": iso(end + timedelta(hours=c.slack_hours))},
                "streams": c.streams, "fields_in_order": ["timestamp", "source", "level", "message"]}
        req = urllib.request.Request(
            c.graylog_url.rstrip("/") + "/api/views/search/messages", method="POST",
            data=json.dumps(body).encode(),
            headers={"Authorization": "Basic " + base64.b64encode(f"{c.token}:token".encode()).decode(),
                     "X-Requested-By": "graylog-exporter", "Content-Type": "application/json", "Accept": "text/csv"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                text = r.read().decode("utf-8")
        except Exception as e:
            raise GraylogError(str(e)) from e
        return parse_csv(text)
