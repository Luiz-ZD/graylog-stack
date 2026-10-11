#!/usr/bin/env bash
# Instala via install.sh em modo --lab (prefixos no scratchpad, projeto graylog-lab2) e valida.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
LAB="${LAB:-/tmp/graylog-lab}"
I="$LAB/inst-$(date +%s)"; export STACK_OPT="$I/opt" STACK_ETC="$I/etc" STACK_VAR="$I/var" COMPOSE_PROJECT=graylog-lab2
fail() { echo "FALHOU: $*"; exit 1; }
# libera portas: derruba o lab de desenvolvimento e instalacoes de teste anteriores
for c in $(docker ps -aq --filter label=com.docker.compose.project=graylog-lab2); do docker rm -f "$c" >/dev/null 2>&1; done
docker network rm graylog-lab2_internal graylog-lab2_public >/dev/null 2>&1
"$HERE/tests/lab/s3up.sh" down >/dev/null 2>&1; "$HERE/tests/lab/lab.sh" down >/dev/null 2>&1
docker build -q --build-arg PYTHON_IMAGE="$(grep ^PYTHON_IMAGE "$HERE/versions.env" | cut -d= -f2)" -t graylog-exporter:bundle "$HERE/exporter" >/dev/null || fail "build exporter"
mkdir -p "$I"; cp "$HERE/install.conf.example" "$I/install.conf"
sed -i 's/^HOST_IP=.*/HOST_IP=127.0.0.1/;s/^GL_HEAP=.*/GL_HEAP=1g/;s/^OS_HEAP=.*/OS_HEAP=1g/;s#^OCI_CONFIG_FILE=.*#OCI_CONFIG_FILE=/nao-existe#' "$I/install.conf"
"$HERE/scripts/install.sh" --conf "$I/install.conf" --lab --dry-run | tail -2
[ ! -e "$STACK_ETC/stack.env" ] || fail "dry-run alterou o sistema"
"$HERE/scripts/install.sh" --conf "$I/install.conf" --lab > "$I/install.log" 2>&1 || { tail -15 "$I/install.log"; fail "install.sh"; }
tail -4 "$I/install.log"
[ "$(stat -c %a "$STACK_ETC/stack.env")" = 600 ] || fail "stack.env deve ser 600"
[ "$(stat -c %a "$STACK_ETC/admin-password")" = 600 ] || fail "admin-password deve ser 600"
grep -q "$(cat "$STACK_ETC/admin-password")" "$I/install.log" && fail "senha impressa no log"
"$STACK_OPT/scripts/verify.sh" || fail "verify.sh"
H1=$(sha256sum "$STACK_ETC/stack.env" "$STACK_ETC/admin-password" | sha256sum)
"$HERE/scripts/install.sh" --conf "$I/install.conf" --lab > "$I/install2.log" 2>&1 || { tail -15 "$I/install2.log"; fail "segunda execucao"; }
H2=$(sha256sum "$STACK_ETC/stack.env" "$STACK_ETC/admin-password" | sha256sum)
[ "$H1" = "$H2" ] || fail "install.sh nao eh idempotente (segredos mudaram)"
grep -q 'stack.env atualizado' "$I/install2.log" || fail "segunda execucao deveria atualizar stack.env mantendo segredos"
"$STACK_OPT/scripts/verify.sh" | tail -1
echo INSTALL_LAB_OK
