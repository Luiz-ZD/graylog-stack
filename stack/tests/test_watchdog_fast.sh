#!/usr/bin/env bash
# Vigia sem Docker: status.json sem updated_at nao pode derrubar o script; lacuna de dados recente deve alertar.
set -uo pipefail
W="$(cd "$(dirname "$0")/.." && pwd)/scripts/watchdog.sh"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/var/export/state" "$T/etc"; printf 'EXPORT_ENABLED=true\nPORT_HTTP=1\nWATCHDOG_THRESHOLD_MIN=10\n' > "$T/etc/stack.env"
run() { STACK_ENV="$T/etc/stack.env" STACK_VAR="$T/var" STACK_ETC="$T/etc" COMPOSE_PROJECT=nao-existe "$W" 2>/dev/null; }
fail() { echo "FALHOU: $*"; exit 1; }
echo '{}' > "$T/var/export/state/status.json"; rm -f "$T/var/watchdog.json"
run && fail "status.json vazio deveria alertar"
[ -s "$T/var/watchdog.json" ] || fail "watchdog.json nao foi escrito (script abortou)"
jq -e 'any(.[]; test("sem batimento"))' "$T/var/watchdog.json" >/dev/null || fail "motivo 'sem batimento' ausente: $(cat "$T/var/watchdog.json")"
NOW=$(date +%s); printf '{"updated_at":%s,"checkpoint":"%s","last_gap":{"ts":"%s","why":"checkpoint muito antigo (x)"}}' "$NOW" "$(date -u +%FT%TZ)" "$(date -u +%FT%TZ)" > "$T/var/export/state/status.json"
run && fail "lacuna recente deveria alertar"
jq -e 'any(.[]; test("lacuna de dados"))' "$T/var/watchdog.json" >/dev/null || fail "motivo 'lacuna de dados' ausente: $(cat "$T/var/watchdog.json")"
printf '{"updated_at":%s,"checkpoint":"%s","last_gap":{"ts":"2020-01-01T00:00:00Z","why":"antigo"}}' "$NOW" "$(date -u +%FT%TZ)" > "$T/var/export/state/status.json"
run; jq -e 'any(.[]; test("lacuna de dados"))' "$T/var/watchdog.json" >/dev/null && fail "lacuna de 2020 nao deve alertar mais"
echo WATCHDOG_FAST_OK
