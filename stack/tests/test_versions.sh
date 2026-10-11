#!/usr/bin/env bash
# 4 imagens fixadas por digest
n=$(grep -c '_IMAGE=.*@sha256:' "$(dirname "$0")/../versions.env"); [ "$n" = 4 ] && echo "versions.env: $n/4 imagens com digest"
