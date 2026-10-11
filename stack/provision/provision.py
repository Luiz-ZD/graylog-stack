#!/usr/bin/env python3
"""Provisionamento idempotente do Graylog (stdlib). Uso:
provision.py --url http://127.0.0.1:9000 --admin-password PW --token-file /etc/graylog-stack/exporter.token"""
import argparse, base64, json, os, secrets, time, urllib.error, urllib.request

INPUTS = [
    ("Syslog-Windows-TCP3514", "org.graylog2.inputs.syslog.tcp.SyslogTCPInput",
     {"bind_address": "0.0.0.0", "port": 3514, "recv_buffer_size": 1048576, "number_worker_threads": 4,
      "tcp_keepalive": False, "use_null_delimiter": False, "tls_enable": False, "max_message_size": 2097152,
      "override_source": None, "charset_name": "UTF-8", "force_rdns": False, "allow_override_date": True,
      "store_full_message": False, "expand_structured_data": False, "timezone": "NotSet"}),
    ("Syslog-RedeLinux-UDP4514", "org.graylog2.inputs.syslog.udp.SyslogUDPInput",
     {"bind_address": "0.0.0.0", "port": 4514, "recv_buffer_size": 8388608, "number_worker_threads": 4,
      "override_source": None, "charset_name": "UTF-8", "force_rdns": False, "allow_override_date": True,
      "store_full_message": False, "expand_structured_data": False, "timezone": "NotSet"}),
]
DEFAULT_STREAM = "000000000000000000000001"


class Api:
    def __init__(self, url, user, pw):
        self.base = url.rstrip("/") + "/api/"
        self.auth = "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode()

    def call(self, method, path, body=None):
        req = urllib.request.Request(self.base + path, method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Authorization": self.auth, "X-Requested-By": "provision",
                     "Content-Type": "application/json", "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise SystemExit(f"{method} {path} -> {e.code}: {e.read().decode()[:400]}")


def wait_ready(api, tries=60):
    for _ in range(tries):
        try:
            api.call("GET", "system")
            return
        except (SystemExit, urllib.error.URLError, ConnectionError, OSError):
            time.sleep(5)
    raise SystemExit("Graylog nao ficou pronto")


def ensure_inputs(api):
    have = {i["title"] for i in api.call("GET", "system/inputs")["inputs"]}
    for title, typ, cfg in INPUTS:
        if title in have:
            print("input ok:", title); continue
        r = api.call("POST", "system/inputs", {"title": title, "type": typ, "global": True, "configuration": cfg})
        print("input criado:", title, r["id"])


def ensure_index_set(api):
    sets = api.call("GET", "system/indices/index_sets")["index_sets"]
    d = next(s for s in sets if s["default"])
    d.update({"shards": 1, "replicas": 0, "use_legacy_rotation": True, "data_tiering": None,
              "rotation_strategy_class": "org.graylog2.indexer.rotation.strategies.SizeBasedRotationStrategy",
              "rotation_strategy": {"type": "org.graylog2.indexer.rotation.strategies.SizeBasedRotationStrategyConfig", "max_size": 1073741824},
              "retention_strategy_class": "org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy",
              "retention_strategy": {"type": "org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig", "max_number_of_indices": 10}})
    api.call("PUT", f"system/indices/index_sets/{d['id']}", d)
    print("index set 1GBx10 ok")


def ensure_pipeline(api, rule_src):
    rules = api.call("GET", "system/pipelines/rule")
    if not any(r["title"] == "win_extrai_campos" for r in rules):
        api.call("POST", "system/pipelines/rule", {"title": "win_extrai_campos", "description": "WinCollect: Level e EventType", "source": rule_src})
    pipes = api.call("GET", "system/pipelines/pipeline")
    p = next((x for x in pipes if x["title"] == "Windows-WinCollect"), None)
    if not p:
        src = 'pipeline "Windows-WinCollect"\nstage 0 match either\nrule "win_extrai_campos"\nend'
        p = api.call("POST", "system/pipelines/pipeline", {"title": "Windows-WinCollect", "description": "", "source": src})
    conns = api.call("GET", "system/pipelines/connections")
    if not any(c["stream_id"] == DEFAULT_STREAM and p["id"] in c["pipeline_ids"] for c in conns):
        api.call("POST", "system/pipelines/connections/to_stream", {"stream_id": DEFAULT_STREAM, "pipeline_ids": [p["id"]]})
    print("pipeline ok")


def ensure_service_user(api, token_file):
    if os.path.exists(token_file) and os.path.getsize(token_file) > 20:
        print("svc-export ok (token ja existe)"); return
    users = api.call("GET", "users")["users"]
    u = next((x for x in users if x["username"] == "svc-export"), None)
    if not u:
        api.call("POST", "users", {"username": "svc-export", "password": secrets.token_urlsafe(24),
            "first_name": "svc", "last_name": "export", "email": "svc-export@localhost", "roles": ["Reader"],
            "permissions": ["streams:read", "messages:read", "messages:analyze", "indexercluster:read"]})
        u = next(x for x in api.call("GET", "users")["users"] if x["username"] == "svc-export")
    for t in api.call("GET", f"users/{u['id']}/tokens").get("tokens", []):
        if t["name"] == "exporter":
            api.call("DELETE", f"users/{u['id']}/tokens/{t['id']}")
    tok = api.call("POST", f"users/{u['id']}/tokens/exporter", {})["token"]
    fd = os.open(token_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(tok)
    print("svc-export token gravado em", token_file)


def resolve_password(argv_value, env):
    """A senha vem de GRAYLOG_ADMIN_PASSWORD (nao aparece no ps); --admin-password segue aceito."""
    pw = env.get("GRAYLOG_ADMIN_PASSWORD") or argv_value
    if not pw:
        raise SystemExit("informe GRAYLOG_ADMIN_PASSWORD (ou --admin-password)")
    return pw


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--url", required=True)
    a.add_argument("--admin-password", default=None)
    a.add_argument("--token-file", required=True)
    a.add_argument("--rule", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "win_rule.pipeline"))
    a = a.parse_args()
    api = Api(a.url, "admin", resolve_password(a.admin_password, os.environ))
    wait_ready(api); ensure_inputs(api); ensure_index_set(api)
    ensure_pipeline(api, open(a.rule).read()); ensure_service_user(api, a.token_file)
    print("PROVISION_DONE")


if __name__ == "__main__":
    main()
