#!/usr/bin/env bash
# Sinal "sem eventos novos": usa o contador de entrada do Graylog (nao depende de retencao); desligavel por WATCHDOG_IDLE_CHECK=false.
set -uo pipefail
W="$(cd "$(dirname "$0")/.." && pwd)/scripts/watchdog.sh"; T="$(mktemp -d)"; PORT=18099
python3 - "$T" $PORT >/dev/null 2>&1 <<'PY' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
T = sys.argv[1]
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.endswith("inputstates"): b = {"states": [{"state": "RUNNING"}]}
        elif self.path.endswith("org.graylog2.throughput.input"): b = {"count": int(open(T + "/count").read())}
        else: b = {}
        d = json.dumps(b).encode(); self.send_response(200); self.send_header("Content-Length", str(len(d))); self.end_headers(); self.wfile.write(d)
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", int(sys.argv[2])), H).serve_forever()
PY
SP=$!; trap 'kill $SP 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/var" "$T/etc"; echo tok > "$T/etc/exporter.token"; echo 100 > "$T/count"; sleep 1
printf 'EXPORT_ENABLED=false\nPORT_HTTP=%s\nWATCHDOG_THRESHOLD_MIN=10\n' $PORT > "$T/etc/stack.env"
run() { STACK_ENV="$T/etc/stack.env" STACK_VAR="$T/var" STACK_ETC="$T/etc" COMPOSE_PROJECT=nao-existe "$W" 2>/dev/null; }
idle() { jq -e 'any(.[]; test("nenhum evento novo"))' "$T/var/watchdog.json" >/dev/null; }
fail() { echo "FALHOU: $*"; exit 1; }
run; idle && fail "primeira leitura nao deve alertar"
echo "100 $(( $(date +%s) - 700 ))" > "$T/var/watchdog.state"; run; idle || fail "contador parado ha 11 min deveria alertar: $(cat "$T/var/watchdog.json")"
echo 150 > "$T/count"; run; idle && fail "contador subiu: nao deve alertar"
echo "150 $(( $(date +%s) - 700 ))" > "$T/var/watchdog.state"; echo 3 > "$T/count"; run; idle && fail "contador menor (Graylog reiniciou) e atividade: nao deve alertar"
echo "3 $(( $(date +%s) - 700 ))" > "$T/var/watchdog.state"; printf 'EXPORT_ENABLED=false\nPORT_HTTP=%s\nWATCHDOG_IDLE_CHECK=false\n' $PORT > "$T/etc/stack.env"; run; idle && fail "WATCHDOG_IDLE_CHECK=false deve desligar"
echo WATCHDOG_IDLE_OK
