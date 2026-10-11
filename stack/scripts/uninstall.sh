#!/usr/bin/env bash
# Uso: uninstall.sh [--purge]   (sem --purge mantém os dados)
set -euo pipefail
ETC="${STACK_ETC:-/etc/graylog-stack}"; OPT="${STACK_OPT:-/opt/graylog-stack}"; VAR="${STACK_VAR:-/var/lib/graylog-stack}"; P="${COMPOSE_PROJECT:-graylog-stack}"
docker compose --env-file "$ETC/stack.env" -f "$OPT/docker-compose.yml" -p "$P" down
if [ -f /etc/systemd/system/graylog-stack-watchdog.timer ]; then
  systemctl disable --now graylog-stack-watchdog.timer 2>/dev/null || true
  rm -f /etc/systemd/system/graylog-stack-watchdog.service /etc/systemd/system/graylog-stack-watchdog.timer /usr/local/bin/graylog-stack
fi
if [ "${1:-}" = "--purge" ]; then
  [ -n "$VAR" ] && [ -n "$ETC" ] && [ -n "$OPT" ] || { echo "caminhos vazios, abortando"; exit 1; }
  rm -rf -- "$VAR" "$ETC" "$OPT" /etc/sysctl.d/99-graylog-stack.conf; echo "dados removidos"
else echo "containers parados; dados mantidos em $VAR (use --purge para apagar)"; fi
