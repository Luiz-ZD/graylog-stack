#!/usr/bin/env bash
# Confere a evidencia mais recente da suite de resiliencia: nenhum FAIL e pelo menos 10 PASS.
f=$(ls -t "$(dirname "$0")"/../../../docs/report/evidencias/resilience-*.txt | head -1)
p=$(grep -c ' PASS ' "$f"); x=$(grep -c ' FAIL ' "$f"); s=$(grep -c ' SKIP ' "$f")
echo "$(basename "$f"): PASS=$p FAIL=$x SKIP=$s"
[ "$x" = 0 ] && [ "$p" -ge 10 ] && echo RESILIENCE_OK
