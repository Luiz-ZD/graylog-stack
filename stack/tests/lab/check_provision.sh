#!/usr/bin/env bash
set -euo pipefail
LAB="${LAB:-/tmp/graylog-lab}"
. "$LAB/etc/stack.env"; U=http://127.0.0.1:9000/api; A="admin:$ADMIN_PASSWORD"
g() { curl -fsS -u "$A" -H 'X-Requested-By: t' "$U/$1"; }
fail() { echo "FALHOU: $*"; exit 1; }
[ "$(g system/inputs | jq '[.inputs[]|select(.title|test("Syslog-"))]|length')" = 2 ] || fail "2 inputs"
[ "$(g system/inputstates | jq '[.states[]|select(.state=="RUNNING")]|length')" = 2 ] || fail "inputs RUNNING"
g system/inputs | jq -e '[.inputs[]|.attributes.bind_address]|all(.=="0.0.0.0")' >/dev/null || fail "bind 0.0.0.0"
g system/indices/index_sets | jq -e '.index_sets[]|select(.default)|(.retention_strategy.max_number_of_indices==10 and .rotation_strategy.max_size==1073741824 and .replicas==0 and .shards==1)' >/dev/null || fail "index set 1GBx10"
g system/pipelines/rule | jq -e '[.[]|select(.title=="win_extrai_campos")]|length==1' >/dev/null || fail "regra pipeline"
g system/pipelines/connections | jq -e '[.[]|select(.stream_id=="000000000000000000000001")]|length==1' >/dev/null || fail "pipeline ligado ao Default Stream"
T=$(cat "$LAB/etc/exporter.token"); curl -fsS -u "$T:token" "$U/system" >/dev/null || fail "token svc-export"
code=$(curl -s -o /dev/null -w '%{http_code}' -u "$T:token" -X DELETE -H 'X-Requested-By: t' "$U/system/inputs/000000000000000000000000"); echo "$code" | grep -qE '^(401|403)$' || fail "svc-export deve ser somente leitura (HTTP $code)"
echo PROVISION_OK
