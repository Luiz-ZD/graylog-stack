#!/usr/bin/env bash
set -uo pipefail
LAB="${LAB:-/tmp/graylog-lab}"
HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/../../scripts/watchdog.sh"
export STACK_ENV="$LAB/etc/stack.env" STACK_VAR="$LAB/var" STACK_ETC="$LAB/etc" COMPOSE_PROJECT=graylog-lab
fail() { echo "FALHOU: $*"; exit 1; }
python3 "$HERE/send_logs.py" --kind linux --proto udp --count 5 --level 6 --tag wd >/dev/null; sleep 15
"$W" 2>/tmp/wd.err || fail "deveria estar saudavel: $(cat /tmp/wd.err)"; echo "saudavel: ok"
docker stop graylog-lab-exporter-1 >/dev/null
"$W" 2>/tmp/wd.err && fail "exporter parado deveria falhar"; grep -q 'container exporter' /tmp/wd.err || fail "motivo ausente: $(cat /tmp/wd.err)"
jq -e 'length>=1' "$LAB/var/watchdog.json" >/dev/null || fail "watchdog.json sem motivo"; echo "exporter parado detectado: $(head -1 /tmp/wd.err)"
docker start graylog-lab-exporter-1 >/dev/null
for i in $(seq 1 24); do "$W" 2>/dev/null && { echo WATCHDOG_OK; exit 0; }; sleep 10; done
fail "nao recuperou apos religar o exporter: $(cat /tmp/wd.err)"
