#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
for pair in "docker c1" "podman c1" "podman c2" "docker c2"; do set -- $pair; echo "######## INICIO $1 $2"; "$D/bench-cold.sh" "$1" "$2" 2>&1; echo "######## FIM $1 $2"; sleep 5; done; echo "######## COLD PRONTO"
