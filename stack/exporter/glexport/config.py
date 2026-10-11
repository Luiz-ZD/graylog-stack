import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    graylog_url: str
    token: str
    streams: list
    export_filter: str
    exclude_sources: list
    state_dir: str
    spool_dir: str
    tz: str
    lag_min: int
    slack_hours: int
    max_catchup_min: int
    journal_max_backlog: int
    enabled: bool
    remote: str
    bucket: str
    prefix: str
    rclone_conf: str


def load(env=os.environ):
    g = lambda k, d=None: env.get(k, d)
    token = g("GRAYLOG_TOKEN") or open(g("GRAYLOG_TOKEN_FILE", "/run/secrets/exporter.token")).read().strip()
    return Config(
        graylog_url=g("GRAYLOG_URL", "http://graylog:9000"), token=token,
        streams=[s for s in g("EXPORT_STREAMS", "000000000000000000000001").split(",") if s],
        export_filter=g("EXPORT_FILTER", "level:[0 TO 3] OR win_level:(Critical OR Error OR Warning) OR win_event_type:16"),
        exclude_sources=[s for s in g("EXPORT_EXCLUDE_SOURCES", "").split(",") if s],
        state_dir=g("STATE_DIR", "/data/state"), spool_dir=g("SPOOL_DIR", "/data/spool"),
        tz=g("TZ", "America/Sao_Paulo"), lag_min=int(g("LAG_MIN", "1")), slack_hours=int(g("SLACK_HOURS", "8760")),
        max_catchup_min=int(g("MAX_CATCHUP_MIN", "720")), journal_max_backlog=int(g("JOURNAL_MAX_BACKLOG", "20000")), enabled=g("EXPORT_ENABLED", "false").lower() == "true",
        remote=g("RCLONE_REMOTE", "oci"), bucket=g("OCI_BUCKET", ""), prefix=g("OCI_PREFIX", ""),
        rclone_conf=g("RCLONE_CONF", "/run/rclone.conf"))
