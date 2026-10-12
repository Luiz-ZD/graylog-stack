#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
until grep -q 'COLD PRONTO' /tmp/bench-cold.log; do sleep 5; done
sleep 20
"$D/run-all.sh"
