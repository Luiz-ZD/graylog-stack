#!/usr/bin/env bash
# Constroi o bundle, extrai, apaga as tags locais das imagens (força docker load) e instala a partir dele.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
LAB="${LAB:-/tmp/graylog-lab}"
X="$LAB/bt-$(date +%s)"; export STACK_OPT="$X/opt" STACK_ETC="$X/etc" STACK_VAR="$X/var" COMPOSE_PROJECT=graylog-lab3
fail() { echo "FALHOU: $*"; exit 1; }
for p in graylog-lab graylog-lab2 graylog-lab3; do for c in $(docker ps -aq --filter label=com.docker.compose.project=$p); do docker rm -f "$c" >/dev/null 2>&1; done; docker network rm ${p}_internal ${p}_public >/dev/null 2>&1; done
"$HERE/scripts/build-bundle.sh" > "$LAB/bundle-build.log" 2>&1 || { tail -8 "$LAB/bundle-build.log"; fail "build-bundle"; }
tail -2 "$LAB/bundle-build.log"
T="$(ls -t "$ROOT"/build/graylog-bundle-*.tar.gz | head -1)"; mkdir -p "$X/x"; tar -C "$X/x" -xzf "$T"; B="$(ls -d "$X"/x/graylog-bundle-*)"
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || fail "SHA256SUMS apos extracao"
grep -rqE 'sha256:|@sha256' "$B/versions.env" && fail "versions.env do bundle nao deve depender de digest/pull"
while read -r ref id; do docker rmi "$ref" >/dev/null 2>&1; done < "$B/images/IMAGE_IDS"
cp "$B/install.conf.example" "$X/install.conf"
sed -i 's/^HOST_IP=.*/HOST_IP=127.0.0.1/;s/^GL_HEAP=.*/GL_HEAP=1g/;s/^OS_HEAP=.*/OS_HEAP=1g/;s#^OCI_CONFIG_FILE=.*#OCI_CONFIG_FILE=/nao-existe#' "$X/install.conf"
S=$(date +%s); "$B/scripts/install.sh" --conf "$X/install.conf" --lab > "$X/install.log" 2>&1 || { tail -15 "$X/install.log"; fail "install do bundle"; }
echo "install.sh: $(( $(date +%s) - S )) s"; grep -E 'imagens carregadas' "$X/install.log"
"$STACK_OPT/scripts/verify.sh" | tail -1 || fail "verify"
{ echo "# Métricas do bundle ($(date -Is))"; echo "- tarball: $(du -h "$T" | cut -f1)  | extraído: $(du -sh "$B" | cut -f1)"; echo "- install.sh a partir do tarball: $(( $(date +%s) - S )) s"; echo "- imagens (docker):"; docker images --format '  - {{.Repository}}:{{.Tag}} {{.Size}}' | grep -E 'graylog-bundle'; } > "$ROOT/docs/report/bundle.md"
docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' | grep graylog-lab3 >> "$ROOT/docs/report/bundle.md"
echo BUNDLE_TEST_OK
