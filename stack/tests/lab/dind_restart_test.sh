#!/usr/bin/env bash
# R2 isolado: instala o bundle num Docker separado (docker:dind), reinicia o daemon e confere a recuperacao.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
LAB="${LAB:-/tmp/graylog-lab}"; N=lab-dind
fail() { echo "FALHOU: $*"; exit 1; }
I() { docker exec "$N" bash -c "$1"; }
T="$(ls -t "$ROOT"/build/graylog-bundle-*.tar.gz | head -1)"; X="$LAB/dind-bundle"; mkdir -p "$X"; tar -C "$X" -xzf "$T"; B="$(ls -d "$X"/graylog-bundle-* | head -1)"
docker build -q -t lab-dind-test - >/dev/null <<'EOD' || fail "build da imagem de teste"
FROM docker:dind
RUN apk add --no-cache bash coreutils openssl curl python3 jq iproute2 gawk sed grep findutils util-linux
EOD
docker rm -f $N >/dev/null 2>&1
docker run -d --name $N --privileged -e DOCKER_TLS_CERTDIR= -v "$LAB/dind-data:/var/lib/docker" -v "$B:/bundle:ro" -v "$HERE:/lab:ro" lab-dind-test >/dev/null || fail "run dind"
for i in $(seq 1 30); do I 'docker info >/dev/null 2>&1' && break; sleep 2; done; I 'docker info >/dev/null 2>&1' || fail "dockerd interno nao subiu"
I 'cp /bundle/install.conf.example /tmp/install.conf && sed -i "s/^HOST_IP=.*/HOST_IP=127.0.0.1/;s/^GL_HEAP=.*/GL_HEAP=1g/;s/^OS_HEAP=.*/OS_HEAP=1g/;s#^OCI_CONFIG_FILE=.*#OCI_CONFIG_FILE=/nao-existe#" /tmp/install.conf'
S=$(date +%s); I '/bundle/scripts/install.sh --conf /tmp/install.conf --lab' > "$LAB/dind-install.log" 2>&1 || { tail -15 "$LAB/dind-install.log"; fail "install.sh dentro do dind"; }
echo "install.sh no dind: $(( $(date +%s) - S )) s"
I '/opt/graylog-stack/scripts/verify.sh' | tail -1 | grep -q VERIFY_OK || fail "verify antes do restart"
I 'python3 /lab/send_logs.py --kind linux --proto udp --count 20 --level 6 --src PRE-RESTART --tag pre >/dev/null; sleep 10; docker exec graylog-stack-opensearch-1 curl -s "localhost:9200/graylog_*/_count?q=source:PRE-RESTART" | jq .count' | grep -qx 20 || fail "ingestao antes do restart"
echo "== reiniciando o daemon (docker restart do dind = dockerd stop/start; sem live-restore) =="
docker restart $N >/dev/null
for i in $(seq 1 30); do I 'docker info >/dev/null 2>&1' && break; sleep 2; done
OK=0; for i in $(seq 1 60); do n=$(I 'docker ps --format "{{.Names}} {{.Status}}" | grep -c "(healthy)"' 2>/dev/null); [ "$n" = 4 ] && { OK=1; break; }; sleep 10; done
[ $OK = 1 ] || { I 'docker ps -a --format "{{.Names}} {{.Status}}"'; fail "stack nao voltou sozinha apos reiniciar o daemon"; }
I '/opt/graylog-stack/scripts/verify.sh' | tail -1 | grep -q VERIFY_OK || fail "verify apos restart"
I 'python3 /lab/send_logs.py --kind linux --proto udp --count 20 --level 6 --src POST-RESTART --tag post >/dev/null; sleep 10; docker exec graylog-stack-opensearch-1 curl -s "localhost:9200/graylog_*/_count?q=source:POST-RESTART" | jq .count' | grep -qx 20 || fail "ingestao depois do restart"
I 'docker exec graylog-stack-opensearch-1 curl -s "localhost:9200/graylog_*/_count?q=source:PRE-RESTART" | jq .count' | grep -qx 20 || fail "dados anteriores perdidos no restart"
echo DIND_RESTART_OK
