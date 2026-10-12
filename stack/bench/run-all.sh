#!/usr/bin/env bash
# Rodadas completas em ordem ABBA (docker, podman, podman, docker) para cancelar efeito de ordem/cache.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
for pair in "docker r1" "podman r1" "podman r2" "docker r2"; do
  set -- $pair; echo "######## INICIO $1 $2 $(date +%T)"; "$D/bench.sh" "$1" "$2" 2>&1; echo "######## FIM $1 $2 $(date +%T)"; sleep 20
done
echo "######## TUDO PRONTO"
