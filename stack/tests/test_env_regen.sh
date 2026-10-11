#!/usr/bin/env bash
# write_stack_env: regenera o que vem do install.conf a cada execucao, preserva segredos e o estado de EXPORT_ENABLED.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FALHOU: $*"; exit 1; }
printf 'GRAYLOG_IMAGE=g:1\n# graylog tag=1\nEXPORTER_IMAGE=e:1\n' > "$T/versions.env"
# shellcheck source=/dev/null
. "$D/scripts/lib-env.sh" 2>/dev/null || fail "scripts/lib-env.sh ausente"
STACK_VAR=/v STACK_ETC=/e TZ=America/Sao_Paulo HOST_IP=1.1.1.1 GL_HEAP=1g OS_HEAP=1g PORT_HTTP=9000 PORT_WIN=3514 PORT_LIN=4514
EXPORT_ENABLED=false OCI_NAMESPACE=n OCI_BUCKET=bucket-A OCI_PREFIX=p/ OCI_REGION=r OCI_COMPARTMENT=c OCI_PROFILE=DEFAULT
EXPORT_FILTER='level:[0 TO 3] OR x' EXPORT_EXCLUDE_SOURCES='H-1' WATCHDOG_THRESHOLD_MIN=10
WATCHDOG_IDLE_CHECK=true; write_stack_env "$T/stack.env" "$T/versions.env"
[ -n "${NEW_ADMIN_PASSWORD:-}" ] || fail "primeira execucao deve gerar senha do admin"
grep -q "^OCI_BUCKET='bucket-A'" "$T/stack.env" || fail "bucket inicial"
M1=$(grep ^MONGO_PASSWORD= "$T/stack.env"); S1=$(grep ^GRAYLOG_PASSWORD_SECRET= "$T/stack.env"); H1=$(grep ^GRAYLOG_ROOT_PASSWORD_SHA2= "$T/stack.env")
[ "$(stat -c %a "$T/stack.env")" = 600 ] || fail "modo 600"
# usuario liga a exportacao (graylog-stack export on) e depois edita install.conf + novo bundle
sed -i 's/^EXPORT_ENABLED=.*/EXPORT_ENABLED=true/' "$T/stack.env"
OCI_BUCKET=bucket-B; EXPORT_ENABLED=false; unset NEW_ADMIN_PASSWORD
printf 'GRAYLOG_IMAGE=g:2\n# graylog tag=2\nEXPORTER_IMAGE=e:2\n' > "$T/versions.env"
WATCHDOG_IDLE_CHECK=true; write_stack_env "$T/stack.env" "$T/versions.env"
grep -q "^OCI_BUCKET='bucket-B'" "$T/stack.env" || fail "edicao do install.conf ignorada"
grep -q '^GRAYLOG_IMAGE=g:2' "$T/stack.env" || fail "novo bundle nao atualizou as imagens"
[ "$(grep -c '^GRAYLOG_IMAGE=' "$T/stack.env")" = 1 ] || fail "chave duplicada"
[ "$M1" = "$(grep ^MONGO_PASSWORD= "$T/stack.env")" ] && [ "$S1" = "$(grep ^GRAYLOG_PASSWORD_SECRET= "$T/stack.env")" ] && [ "$H1" = "$(grep ^GRAYLOG_ROOT_PASSWORD_SHA2= "$T/stack.env")" ] || fail "segredos mudaram"
[ -z "${NEW_ADMIN_PASSWORD:-}" ] || fail "nao deve gerar nova senha do admin"
grep -q "^EXPORT_ENABLED='true'" "$T/stack.env" || fail "EXPORT_ENABLED ligado pelo CLI nao pode ser revertido pelo install.sh"
grep -q "^EXPORT_FILTER='level:\[0 TO 3\] OR x'" "$T/stack.env" || fail "filtro"
EXPORT_EXCLUDE_SOURCES="it's"
write_stack_env "$T/stack2.env" "$T/versions.env" 2>/dev/null && fail "valor com aspa simples deveria ser recusado"
[ ! -s "$T/stack2.env" ] || fail "nao deve deixar stack.env corrompido"
echo ENV_REGEN_OK
