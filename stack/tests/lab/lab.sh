#!/usr/bin/env bash
# Uso: lab.sh up|down|wait|env|dc   (usa $LAB)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB="${LAB:-/tmp/graylog-lab}"
ENVF="$LAB/etc/stack.env"
mkenv() {
  mkdir -p "$LAB"/etc "$LAB"/var/{mongo,opensearch,graylog,export/state,export/spool}; chmod 700 "$LAB/etc"
  chown -R 1000:1000 "$LAB/var/opensearch"; chown -R 1100:1100 "$LAB/var/graylog"; chown -R 999:999 "$LAB/var/mongo"
  [ -s "$LAB/etc/exporter.token" ] || : > "$LAB/etc/exporter.token"; mkdir -p "$LAB/etc/oci"
  [ -f "$ENVF" ] && return
  pw="$(openssl rand -hex 12)"; sec="$(openssl rand -hex 48)"; admin="LabAdmin$(openssl rand -hex 4)"
  { grep -v '^#' "$ROOT/versions.env"
    echo "STACK_VAR=$LAB/var"; echo "STACK_ETC=$LAB/etc"; echo "TZ=America/Sao_Paulo"; echo "HOST_IP=127.0.0.1"
    echo "GL_HEAP=1g"; echo "OS_HEAP=1g"; echo "MONGO_PASSWORD=$pw"
    echo "GRAYLOG_PASSWORD_SECRET=$sec"
    echo "GRAYLOG_ROOT_PASSWORD_SHA2=$(printf %s "$admin" | sha256sum | cut -d' ' -f1)"
    echo "ADMIN_PASSWORD=$admin"
    echo "PORT_HTTP=9000"; echo "PORT_WIN=3514"; echo "PORT_LIN=4514"
    echo "EXPORTER_IMAGE=graylog-exporter:lab"; echo "EXPORT_ENABLED=false"
    echo "EXPORT_FILTER='level:[0 TO 3] OR win_level:(Critical OR Error OR Warning) OR win_event_type:16'"
    echo "EXPORT_EXCLUDE_SOURCES=EXCLUDED-HOST-01"
  } > "$ENVF"; chmod 600 "$ENVF"
}
dc() {
  local f=(-f "$ROOT/docker-compose.yml"); [ -f "$LAB/etc/override.yml" ] && f+=(-f "$LAB/etc/override.yml")
  docker compose --env-file "$ENVF" "${f[@]}" -p graylog-lab "$@"
}
case "${1:-}" in
  env) mkenv; echo "$ENVF" ;;
  build) # baixa as imagens fixadas e constroi a imagem do exportador (precisa do rclone no PATH)
        . "$ROOT/versions.env"; for i in $GRAYLOG_IMAGE $OPENSEARCH_IMAGE $MONGO_IMAGE $PYTHON_IMAGE; do docker pull -q "$i" >/dev/null; done
        command -v rclone >/dev/null || { echo "instale o rclone: https://rclone.org/install/"; exit 1; }
        cp "$(command -v rclone)" "$ROOT/exporter/rclone"
        docker build -q --build-arg PYTHON_IMAGE="$PYTHON_IMAGE" -t graylog-exporter:lab "$ROOT/exporter" ;;
  provision) mkenv; . "$ENVF"; GRAYLOG_ADMIN_PASSWORD="$ADMIN_PASSWORD" python3 "$ROOT/provision/provision.py" --url "http://127.0.0.1:${PORT_HTTP:-9000}" --token-file "$LAB/etc/exporter.token" ;;
  up) mkenv; dc up -d "${@:2}" ;;
  down) dc down ${2:-} ;;
  wait) want=$(dc config --services | wc -l)
        for i in $(seq 1 90); do
          have=$(dc ps --format '{{.Health}}' | grep -c '^healthy$' || true)
          [ "$have" = "$want" ] && { echo "todos healthy ($have/$want)"; exit 0; }; sleep 10; done
        dc ps; echo "NAO ficaram healthy ($have/$want)"; exit 1 ;;
  dc) shift; dc "$@" ;;
  *) echo "uso: $0 build|up|wait|provision|down|env|dc"; exit 2 ;;
esac
