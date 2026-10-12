#!/usr/bin/env bash
# Instalacao a FRIO: carrega as imagens do bundle num motor limpo e ISOLADO (nao toca nos containers do host):
#   docker -> um segundo dockerd com data-root/containerd proprios;  podman -> podman --root/--runroot proprios.
# Uso: bench-cold.sh docker|podman RODADA     Saida: ../../docs/report/bench/cold-<motor>-<RODADA>.kv
set -uo pipefail
ENG=${1:?docker|podman}; RUN=${2:?}
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
IMG_DIR=${IMG_DIR:-$ROOT/../build/graylog-bundle-20261011/images}; OUT=${OUT:-$ROOT/../docs/report/bench}; mkdir -p "$OUT"
R="$OUT/cold-$ENG-$RUN.kv"; : > "$R"; D=$(mktemp -d /var/tmp/gcold-XXXXXX); DP=""
kv() { echo "$1=$2" >> "$R"; echo "  $1=$2" >&2; }
now() { date +%s.%N; }; el() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }
pss() { awk '/^Pss:/{s+=$2} END{printf "%d", s}' /proc/$1/smaps_rollup 2>/dev/null; }
CT=""
cleanup() { [ -n "$DP" ] && { kill "$DP" 2>/dev/null; for _ in $(seq 1 30); do kill -0 "$DP" 2>/dev/null || break; sleep 1; done; }; [ -n "$CT" ] && kill "$CT" 2>/dev/null; sleep 1
  case "$D" in /var/tmp/gcold-*) rm -rf -- "$D";; esac; }
trap cleanup EXIT
kv engine "$ENG"
if [ "$ENG" = docker ]; then
  # containerd PROPRIO (raiz, estado e socket isolados): sem isso o dockerd herda o containerd do sistema e ve as imagens do host
  : > "$D/empty.toml"; mkdir -p "$D/ctd-root" "$D/ctd-state"
  containerd --config "$D/empty.toml" --address "$D/ctd.sock" --root "$D/ctd-root" --state "$D/ctd-state" > "$D/ctd.log" 2>&1 & CT=$!
  for i in $(seq 1 30); do [ -S "$D/ctd.sock" ] && break; sleep 1; done
  echo '{}' > "$D/daemon.json"
  dockerd --config-file "$D/daemon.json" --data-root "$D/data" --exec-root "$D/exec" --pidfile "$D/pid" --host "unix://$D/sock" \
    --containerd "$D/ctd.sock" --containerd-namespace gcold --containerd-plugins-namespace gcold-plugins \
    --iptables=false --ip6tables=false --bridge=none --userland-proxy=false > "$D/dockerd.log" 2>&1 & DP=$!
  CLI=(docker -H "unix://$D/sock"); for i in $(seq 1 90); do "${CLI[@]}" info >/dev/null 2>&1 && break; sleep 1; done
  "${CLI[@]}" info >/dev/null 2>&1 || { echo "FALHA: dockerd isolado nao subiu" >&2; tail -5 "$D/dockerd.log" >&2; kv erro dockerd; exit 1; }
  kv images_before "$("${CLI[@]}" images -q | wc -l)"
  sleep 3; kv daemon_idle_zero_containers_mb "$(( ($(pss "$DP") + $(pss "$CT")) / 1024 ))"
  STORE="$D"
else
  CLI=(podman --root "$D/root" --runroot "$D/run"); STORE="$D/root"; kv daemon_idle_zero_containers_mb 0
fi
t0=$(now); for t in "$IMG_DIR"/*.tar; do "${CLI[@]}" load -i "$t" >/dev/null 2>&1 || { echo "FALHA: load $t" >&2; kv erro load; exit 1; }; done
kv image_load_cold_s "$(el $t0 "$(now)")"
kv image_store_mb "$(( $(du -sbx "$STORE" | awk '{print $1}') / 1048576 ))"
if [ "$ENG" = docker ]; then sleep 2; kv daemon_after_load_mb "$(( ($(pss "$DP") + $(pss "$CT")) / 1024 ))"; else kv daemon_after_load_mb 0; fi
kv images "$("${CLI[@]}" images -q | wc -l)"; kv done 1
