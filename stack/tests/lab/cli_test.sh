#!/usr/bin/env bash
set -uo pipefail
LAB="${LAB:-/tmp/graylog-lab}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export STACK_OPT="$HERE/../.." STACK_ETC="$LAB/etc" STACK_VAR="$LAB/var" COMPOSE_PROJECT=graylog-lab
C="$HERE/../../scripts/graylog-stack"
st=$("$C" status 2>&1); echo "$st" | grep -q last_ok || { echo "FALHOU: status sem last_ok"; exit 1; }
out=$("$C" proof 3 2>&1); echo "$out" | tail -4
echo "$out" | grep -qE '^3/3 conferidos no bucket' || { echo "FALHOU: proof 3/3"; exit 1; }
v=$("$C" version); echo "$v" | grep -q '^GRAYLOG_IMAGE=' || { echo "FALHOU: version"; exit 1; }
echo CLI_OK
