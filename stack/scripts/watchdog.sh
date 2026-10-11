#!/usr/bin/env bash
# Sai 1 (motivo em stderr e em $STACK_VAR/watchdog.json) se a stack não está saudável. Limiar: WATCHDOG_THRESHOLD_MIN (10).
set -uo pipefail
STACK_ENV="${STACK_ENV:-/etc/graylog-stack/stack.env}"; . "$STACK_ENV"
STACK_VAR="${STACK_VAR:-/var/lib/graylog-stack}"; STACK_ETC="${STACK_ETC:-/etc/graylog-stack}"
P="${COMPOSE_PROJECT:-graylog-stack}"; T=$(( ${WATCHDOG_THRESHOLD_MIN:-10} * 60 )); NOW=$(date +%s); BAD=()
for s in mongodb opensearch graylog exporter; do
  h=$(docker inspect -f '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${P}-${s}-1" 2>/dev/null | head -1); [ -n "$h" ] || h=ausente
  case "$h" in running/healthy|running/) ;; *) BAD+=("container $s: $h");; esac
done
TOKEN="$(cat "$STACK_ETC/exporter.token" 2>/dev/null)"; API="http://127.0.0.1:${PORT_HTTP:-9000}/api"
st=$(curl -fs -m 10 -u "$TOKEN:token" "$API/system/inputstates" 2>/dev/null) || BAD+=("api do graylog fora")
if [ -n "${st:-}" ] && [ "$(echo "$st" | jq '[.states[]|select(.state!="RUNNING")]|length')" != 0 ]; then BAD+=("input fora de RUNNING"); fi
# contador de mensagens recebidas pelos inputs (nao depende da retencao; zera se o Graylog reinicia, o que conta como atividade)
cnt=$(curl -fs -m 10 -u "$TOKEN:token" "$API/system/metrics/org.graylog2.throughput.input" 2>/dev/null | jq '.count // empty' 2>/dev/null)
SF="$STACK_VAR/watchdog.state"
if [ "${WATCHDOG_IDLE_CHECK:-true}" = true ] && [ -n "${cnt:-}" ]; then
  prev=$(cut -d' ' -f1 "$SF" 2>/dev/null || echo -1); pt=$(cut -d' ' -f2 "$SF" 2>/dev/null || echo "$NOW")
  if [ "$cnt" != "$prev" ]; then echo "$cnt $NOW" > "$SF"
  elif [ $((NOW-pt)) -gt "$T" ]; then BAD+=("nenhum evento novo ha $(( (NOW-pt)/60 )) min"); fi
fi
S="$STACK_VAR/export/state/status.json"
if [ "${EXPORT_ENABLED:-false}" = true ] && [ -f "$S" ]; then
  ua=$(jq -r '(.updated_at // 0)|tonumber? // 0' "$S" 2>/dev/null || echo 0); [ $((NOW-${ua:-0})) -gt "$T" ] && BAD+=("exportador sem batimento")
  a=$(jq '.oldest_spool_age_s // 0' "$S"); [ "$a" -gt "$T" ] && BAD+=("arquivo no spool ha $((a/60)) min")
  e=$(jq -r '.last_error // empty' "$S"); [ -n "$e" ] && BAD+=("ultimo erro do exportador: $e")
  cp=$(jq -r '.checkpoint // empty' "$S" 2>/dev/null); [ -n "$cp" ] && [ $((NOW-$(date -d "$cp" +%s 2>/dev/null || echo "$NOW"))) -gt $((T+120)) ] && BAD+=("checkpoint atrasado")
  gts=$(jq -r '.last_gap.ts // empty' "$S" 2>/dev/null)
  if [ -n "$gts" ] && [ $((NOW-$(date -d "$gts" +%s 2>/dev/null || echo 0))) -lt 86400 ]; then BAD+=("lacuna de dados em $gts: $(jq -r '.last_gap.why' "$S")"); fi
fi
if [ ${#BAD[@]} -gt 0 ]; then printf '%s\n' "${BAD[@]}" >&2; printf '%s\n' "${BAD[@]}" | jq -R . | jq -s . > "$STACK_VAR/watchdog.json"; exit 1; fi
echo '[]' > "$STACK_VAR/watchdog.json"; exit 0
