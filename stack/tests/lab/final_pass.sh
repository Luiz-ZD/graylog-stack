#!/usr/bin/env bash
# Passagem final no lab de desenvolvimento: ponta a ponta, bordas, vigia, CLI e resiliencia (subconjunto afetado pelas correcoes).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; f=0
for t in e2e.sh edge_e2e.sh task7_tests.sh; do echo "### $t"; "$HERE/$t" 2>&1 | tail -3 || f=1; done
echo "### resilience R3 R4 R5 R6 R9 R10"; "$HERE/resilience.sh" R3 R4 R5 R6 R9 R10 2>&1 | grep -E 'PASS|FAIL|SKIP'
echo FINAL_PASS_DONE
