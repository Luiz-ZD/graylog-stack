#!/usr/bin/env bash
# Topologia de rede do compose entregue (sem overrides do lab): o exportador precisa de saida (rede nao-internal) para o OCI;
# mongodb/opensearch ficam so na rede interna.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp)"; trap 'rm -f "$T"' EXIT
for v in GRAYLOG_IMAGE OPENSEARCH_IMAGE MONGO_IMAGE EXPORTER_IMAGE; do echo "$v=x:y"; done > "$T"
printf 'STACK_VAR=/v\nSTACK_ETC=/e\nTZ=UTC\nHOST_IP=1.1.1.1\nGL_HEAP=1g\nOS_HEAP=1g\nMONGO_PASSWORD=p\nGRAYLOG_PASSWORD_SECRET=s\nGRAYLOG_ROOT_PASSWORD_SHA2=h\nPORT_HTTP=9000\nPORT_WIN=3514\nPORT_LIN=4514\nEXPORT_FILTER=f\nEXPORT_EXCLUDE_SOURCES=\n' >> "$T"
J="$(docker compose --env-file "$T" -f "$D/docker-compose.yml" config --format json)" || { echo "FALHOU: compose config"; exit 1; }
egress() { echo "$J" | jq -r --arg s "$1" '[.services[$s].networks|keys[] as $n | .. | empty] | length' >/dev/null 2>&1; echo "$J" | jq -r --arg s "$1" '.services[$s].networks|keys[]' | while read -r n; do echo "$J" | jq -r --arg n "$n" '.networks[$n].internal // false'; done | grep -q false; }
egress exporter || { echo "FALHOU: exporter sem rede com saida (internal:true bloqueia o OCI)"; exit 1; }
for s in mongodb opensearch; do egress $s && { echo "FALHOU: $s tem rede com saida/exposicao"; exit 1; }; done
echo "$J" | jq -e '[.services.exporter.ports // []]|flatten|length==0' >/dev/null || { echo "FALHOU: exporter nao deve publicar portas"; exit 1; }
echo COMPOSE_NETWORKS_OK
