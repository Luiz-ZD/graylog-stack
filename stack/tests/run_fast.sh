#!/usr/bin/env bash
# Suite rapida (sem lab): unitarios do exportador + testes de shell/compose. Imprime FAST_SUITE_OK.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; f=0
( cd "$D/../exporter" && python3 -W ignore -m unittest discover -s tests 2>&1 | tail -3 ) || f=1
( cd "$D" && python3 -W ignore -m unittest test_provision_unit 2>&1 | tail -2 ) || f=1
for t in test_versions.sh test_compose_networks.sh test_env_regen.sh test_watchdog_fast.sh test_watchdog_idle.sh; do
  out=$("$D/$t" 2>&1) || { echo "$t: $out"; f=1; continue; }; echo "$t: $(echo "$out" | tail -1)"
done
[ $f = 0 ] && echo FAST_SUITE_OK || { echo FAST_SUITE_FALHOU; exit 1; }
