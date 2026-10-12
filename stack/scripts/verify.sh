#!/usr/bin/env bash
# Uso: verify.sh [--oci]. Imprime VERIFY_OK e sai 0 se tudo conferir.
set -uo pipefail
ETC="${STACK_ETC:-/etc/graylog-stack}"; OPT="${STACK_OPT:-/opt/graylog-stack}"; VAR="${STACK_VAR:-/var/lib/graylog-stack}"
. "$ETC/stack.env"; P="${COMPOSE_PROJECT:-graylog-stack}"; API="http://127.0.0.1:${PORT_HTTP}/api"; F=0
chk(){ for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do eval "$2" >/dev/null 2>&1 && break; sleep 10; done; if eval "$2" >/dev/null 2>&1; then echo "[ok]    $1"; else echo "[FALHA] $1"; F=1; fi; }
for s in mongodb opensearch graylog exporter; do chk "container $s healthy" "[ \"\$(docker inspect -f '{{.State.Health.Status}}' ${P}-$s-1)\" = healthy ]"; done
chk "API do Graylog" "curl -fs $API/system/lbstatus | grep -qi alive"
T="$(cat "$ETC/exporter.token")"
chk "2 inputs RUNNING" "[ \"\$(curl -fs -u $T:token $API/system/inputstates | jq '[.states[]|select(.state==\"RUNNING\")]|length')\" = 2 ]"
chk "portas ${PORT_HTTP}/tcp ${PORT_WIN}/tcp ${PORT_LIN}/udp escutando" "ss -tulnH | grep -E ':(${PORT_WIN}|${PORT_LIN}|${PORT_HTTP})\b' | wc -l | grep -qE '^[3-9]'"
chk "MongoDB/OpenSearch não publicados" "! ss -tlnH | grep -E ':(27017|9200|9300)\b'"
chk "vigia saudável" "STACK_ENV=$ETC/stack.env STACK_ETC=$ETC STACK_VAR=$VAR COMPOSE_PROJECT=$P $OPT/scripts/watchdog.sh"
if [ "${1:-}" = "--oci" ]; then
  R=oci; obj="${OCI_PREFIX}verify-$(hostname)-$(date +%s).txt"; echo "verify $(date -u +%FT%TZ)" > /tmp/verify.txt
  X="docker exec ${P}-exporter-1 rclone --config /run/rclone.conf"
  chk "OCI: gravar objeto de teste" "docker cp /tmp/verify.txt ${P}-exporter-1:/tmp/v.txt && $X copyto /tmp/v.txt $R:${OCI_BUCKET}/${obj}"
  chk "OCI: ler de volta"           "$X lsjson $R:${OCI_BUCKET}/${obj} | jq -e 'length==1'"
  # Apagar exige permissao extra no bucket e o exportador NAO precisa dela (so grava/le): vira aviso, nao falha.
  if $X deletefile "$R:${OCI_BUCKET}/${obj}" >/dev/null 2>&1; then echo "[ok]    OCI: apagar objeto de teste"
  else echo "[aviso] OCI: sem permissao para apagar o objeto de teste (isso NAO impede o exportador). Remova manualmente: ${OCI_BUCKET}/${obj}"; fi
fi
[ $F = 0 ] && echo VERIFY_OK || { echo VERIFY_FALHOU; exit 1; }
