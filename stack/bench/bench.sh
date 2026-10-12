#!/usr/bin/env bash
# Benchmark Docker x Podman com a MESMA stack (docker-compose.yml), o MESMO bundle de imagens, as mesmas heaps e a mesma carga.
# Uso: bench.sh docker|podman RODADA       (variaveis: LOAD_SEC=300 IDLE_SEC=120 RATE=1250 IMG_DIR=...)
# Saida: ../../docs/report/bench/<motor>-<RODADA>.kv   (chave=valor; compare.py agrega)
set -uo pipefail
ENG=${1:?uso: bench.sh docker|podman RODADA}; RUN=${2:?}
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
IMG_DIR=${IMG_DIR:-$ROOT/../build/graylog-bundle-20261011/images}
OUT=${OUT:-$ROOT/../docs/report/bench}; mkdir -p "$OUT"
LOAD_SEC=${LOAD_SEC:-300}; IDLE_SEC=${IDLE_SEC:-120}; RATE=${RATE:-1250}
W=$(mktemp -d /var/tmp/gbench-XXXXXX); P=gbench; R="$OUT/$ENG-$RUN.kv"; : > "$R"
kv() { echo "$1=$2" >> "$R"; echo "  $1=$2" >&2; }
now() { date +%s.%N; }
el() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }
E() { if [ "$ENG" = podman ]; then podman "$@"; else docker "$@"; fi; }
dc() { if [ "$ENG" = podman ]; then DOCKER_HOST=unix:///run/podman/podman.sock docker compose --env-file "$W/etc/stack.env" -f "$ROOT/docker-compose.yml" -p $P "$@"
       else docker compose --env-file "$W/etc/stack.env" -f "$ROOT/docker-compose.yml" -p $P "$@"; fi; }
cpid() { E inspect -f '{{.State.Pid}}' "$P-$1-1" 2>/dev/null; }
cgdir() { local c; c=$(sed -n 's#^0::##p' /proc/$1/cgroup); c=${c%/container}; echo "/sys/fs/cgroup$c"; }   # mesmo nivel nos dois motores (escopo do container, com shim/conmon)
stat_mb() { awk -v k="$2" '$1==k{printf "%d", $2/1048576}' "$(cgdir "$1")/memory.stat"; }
pss() { awk '/^Pss:/{s+=$2} END{printf "%d", s}' /proc/$1/smaps_rollup 2>/dev/null; }
ticks() { awk '{print $14+$15}' /proc/$1/stat 2>/dev/null; }
health() { E inspect -f '{{.State.Health.Status}}' "$P-$1-1" 2>/dev/null; }
SVCS="mongodb opensearch graylog exporter"
overhead_pids() { # processos do motor atribuiveis a ESTA stack (por container: shim/conmon; docker: proxies das portas)
  local s pp; for s in $SVCS; do pp=$(ps -o ppid= -p "$(cpid $s)" 2>/dev/null | tr -d ' '); [ -n "$pp" ] && echo "$pp"; done
  if [ "$ENG" = docker ]; then pgrep -af docker-proxy | grep -E 'host-port (9000|3514|4514)\b' | awk '{print $1}'; fi; }
daemon_pids() { if [ "$ENG" = docker ]; then pgrep -x dockerd; pgrep -x containerd; else pgrep -f 'podman system service'; pgrep -x aardvark-dns; fi; }
sum_pss() { local t=0 p; for p in "$@"; do t=$((t + $(pss "$p"))); done; echo $t; }
cleanup() { dc down -t 5 >/dev/null 2>&1; case "$W" in /var/tmp/gbench-*) rm -rf -- "$W";; esac; }
trap cleanup EXIT
echo "== $ENG rodada $RUN  ($(E --version | head -1))" >&2
kv engine "$ENG"; kv engine_version "$(E --version | awk '{print $3}')"; kv load_sec "$LOAD_SEC"; kv rate_per_proto "$RATE"
# ---- ambiente (mesmo env de producao, imagens do bundle)
LAB=$W "$ROOT/tests/lab/lab.sh" env >/dev/null
while read -r ref id; do case $ref in */graylog:*) GL=$ref;; */opensearch:*) OS=$ref;; */mongo:*) MG=$ref;; */exporter:*) EX=$ref;; esac; done < "$IMG_DIR/IMAGE_IDS"
sed -i -e "s#^GRAYLOG_IMAGE=.*#GRAYLOG_IMAGE=$GL#" -e "s#^OPENSEARCH_IMAGE=.*#OPENSEARCH_IMAGE=$OS#" -e "s#^MONGO_IMAGE=.*#MONGO_IMAGE=$MG#" -e "s#^EXPORTER_IMAGE=.*#EXPORTER_IMAGE=$EX#" "$W/etc/stack.env"
. "$W/etc/stack.env"
# ---- 1) carregar as imagens do bundle (offline)
E rmi -f "$GL" "$OS" "$MG" "$EX" >/dev/null 2>&1
if [ "$ENG" = docker ]; then ST="/var/lib/docker /var/lib/containerd"; else ST="/var/lib/containers"; fi
d0=$(du -sbx $ST 2>/dev/null | awk '{s+=$1} END{print s}'); t0=$(now)
for t in "$IMG_DIR"/*.tar; do E load -i "$t" >/dev/null 2>&1 || { echo "FALHA: $ENG load $t" >&2; kv erro load; exit 1; }; done
kv image_load_warm_s "$(el $t0 "$(now)")"   # NAO comparavel (cache do motor); veja bench-cold.sh
# ---- 2) subir a stack e medir o tempo ate tudo healthy
dp0=$(sum_pss $(daemon_pids)); kv daemon_pss_before_mb "$((dp0 / 1024))"
t0=$(now); dc up -d >/dev/null 2>&1 || { echo "FALHA: compose up" >&2; dc up -d 2>&1 | tail -5 >&2; kv erro compose_up; exit 1; }
for i in $(seq 1 300); do ok=1; for s in $SVCS; do [ "$(health $s)" = healthy ] || ok=0; done; [ $ok = 1 ] && break; sleep 1; done
[ $ok = 1 ] || { echo "FALHA: nem todos healthy" >&2; kv erro nao_healthy; exit 1; }
kv start_to_healthy_s "$(el $t0 "$(now)")"
GRAYLOG_ADMIN_PASSWORD="$ADMIN_PASSWORD" python3 "$ROOT/provision/provision.py" --url "http://127.0.0.1:$PORT_HTTP" --token-file "$W/etc/exporter.token" >/dev/null 2>&1 || kv aviso provision_falhou
# ---- 3) memoria em repouso
sleep "$IDLE_SEC"
tot=0; an=0; fi=0; for s in $SVCS; do m=$(cat "$(cgdir "$(cpid $s)")/memory.current"); a=$(stat_mb "$(cpid $s)" anon); f=$(stat_mb "$(cpid $s)" file); kv "mem_idle_${s}_mb" "$((m / 1048576))"; kv "mem_idle_${s}_anon_mb" "$a"; tot=$((tot + m)); an=$((an + a)); fi=$((fi + f)); done
kv mem_idle_anon_mb "$an"; kv mem_idle_file_mb "$fi"
kv mem_idle_containers_mb "$((tot / 1048576))"
op=$(sum_pss $(overhead_pids)); kv overhead_procs_mb "$(awk -v k=$op 'BEGIN{printf "%.1f", k/1024}')"
dp1=$(sum_pss $(daemon_pids)); kv daemon_pss_after_mb "$((dp1 / 1024))"; kv daemon_marginal_mb "$(( (dp1 - dp0) / 1024 ))"
kv total_idle_mb "$(awk -v a=$an -v b=$op -v c=$((dp1 - dp0)) 'BEGIN{printf "%.0f", a + b/1024 + (c>0?c/1024:0)}')"   # memoria real (anon) + processos auxiliares + variacao do daemon
# ---- 4) carga sintetica (TCP + UDP pelo IP do host = caminho real, DNAT) e CPU
HIP=$(hostname -I | awk '{print $1}'); TAG="BENCH-$ENG-$RUN"
c0=$(for s in $SVCS; do awk '/^usage_usec/{print $2}' "$(cgdir "$(cpid $s)")/cpu.stat"; done | awk '{s+=$1} END{print s}')
o0=$(for p in $(overhead_pids) $(daemon_pids); do ticks "$p"; done | awk '{s+=$1} END{print s}')
N=$((RATE * LOAD_SEC)); T0=$(now)
python3 "$ROOT/tests/lab/send_logs.py" --host "$HIP" --kind linux --proto tcp --count $N --rate $RATE --level 6 --src "$TAG-TCP" --tag b >/dev/null &
python3 "$ROOT/tests/lab/send_logs.py" --host "$HIP" --kind linux --proto udp --count $N --rate $RATE --level 6 --src "$TAG-UDP" --tag b >/dev/null &
for s in graylog opensearch; do :; done; wait
LT=$(el $T0 "$(now)"); kv load_elapsed_s "$LT"
c1=$(for s in $SVCS; do awk '/^usage_usec/{print $2}' "$(cgdir "$(cpid $s)")/cpu.stat"; done | awk '{s+=$1} END{print s}')
o1=$(for p in $(overhead_pids) $(daemon_pids); do ticks "$p"; done | awk '{s+=$1} END{print s}')
kv cpu_containers_cores "$(awk -v a=$c0 -v b=$c1 -v t=$LT 'BEGIN{printf "%.2f", (b-a)/1e6/t}')"
kv cpu_engine_overhead_cores "$(awk -v a=$o0 -v b=$o1 -v t=$LT 'BEGIN{printf "%.3f", ((b-a)/100)/t}')"
tot=0; an=0; for s in $SVCS; do m=$(cat "$(cgdir "$(cpid $s)")/memory.current"); tot=$((tot + m)); an=$((an + $(stat_mb "$(cpid $s)" anon))); done; kv mem_load_containers_mb "$((tot / 1048576))"; kv mem_load_anon_mb "$an"
sleep 45; E exec "$P-opensearch-1" curl -s -XPOST 'localhost:9200/graylog_*/_refresh' >/dev/null 2>&1
rt=$(E exec "$P-opensearch-1" curl -s "localhost:9200/graylog_*/_count?q=source:$TAG-TCP" | jq .count); ru=$(E exec "$P-opensearch-1" curl -s "localhost:9200/graylog_*/_count?q=source:$TAG-UDP" | jq .count)
kv sent_per_proto "$N"; kv recv_tcp "${rt:-0}"; kv recv_udp "${ru:-0}"
# ---- 5) recuperacao: crash real do graylog (kill -9 do processo no host)
gp=$(cpid graylog); tk=$(now); kill -9 "$gp"
for i in $(seq 1 120); do np=$(cpid graylog); [ -n "$np" ] && [ "$np" != "$gp" ] && [ "$np" != 0 ] && break; sleep 0.5; done; kv recover_restart_s "$(el $tk "$(now)")"
for i in $(seq 1 300); do [ "$(health graylog)" = healthy ] && break; sleep 1; done; kv recover_healthy_s "$(el $tk "$(now)")"
kv done 1
