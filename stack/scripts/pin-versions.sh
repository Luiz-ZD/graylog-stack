#!/usr/bin/env bash
# Resolve tag -> digest e grava stack/versions.env. Uso: pin-versions.sh graylog=7.1.10 opensearch=2.19.6 mongo=7.0.43 python=3.12-slim
set -euo pipefail
OUT="$(dirname "$0")/../versions.env"; : > "$OUT"
declare -A REPO=( [graylog]=graylog/graylog [opensearch]=opensearchproject/opensearch [mongo]=mongo [python]=python )
for kv in "$@"; do
  name="${kv%%=*}"; tag="${kv#*=}"; repo="${REPO[$name]}"
  docker pull -q "$repo:$tag" >/dev/null
  digest="$(docker inspect --format '{{index .RepoDigests 0}}' "$repo:$tag")"
  echo "$(echo "$name" | tr a-z A-Z)_IMAGE=${digest}" >> "$OUT"
  echo "# $name tag=$tag" >> "$OUT"
done
cat "$OUT"
