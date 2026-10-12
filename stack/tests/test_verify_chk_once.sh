#!/usr/bin/env bash
# chk() do verify.sh nao pode executar o comando mais vezes que o necessario: um teste que muda estado
# (ex.: apagar o objeto de teste) falhava na 2a execucao e dava FALHA mesmo quando tinha dado certo.
set -uo pipefail
V="$(cd "$(dirname "$0")/.." && pwd)/scripts/verify.sh"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
grep '^chk()' "$V" > "$T/chk.sh" || { echo "FALHOU: chk() nao encontrado"; exit 1; }
run() { ( F=0; sleep() { :; }; . "$T/chk.sh"; chk "teste" "$1" >"$T/out" 2>&1; echo "$F" > "$T/F" ); }
: > "$T/n"; run "echo x >> $T/n"
[ "$(grep -c x "$T/n")" = 1 ] || { echo "FALHOU: comando que passa deve rodar 1 vez (rodou $(grep -c x "$T/n"))"; exit 1; }
grep -q '^\[ok\]' "$T/out" && [ "$(cat "$T/F")" = 0 ] || { echo "FALHOU: deveria reportar ok"; exit 1; }
: > "$T/n"; run "echo x >> $T/n; false"
[ "$(grep -c x "$T/n")" = 12 ] || { echo "FALHOU: comando que falha deve rodar 12 vezes (rodou $(grep -c x "$T/n"))"; exit 1; }
grep -q '^\[FALHA\]' "$T/out" && [ "$(cat "$T/F")" = 1 ] || { echo "FALHOU: deveria reportar FALHA"; exit 1; }
# destrutivo: 1a execucao apaga (passa), qualquer reexecucao falha. Tem que dar ok.
touch "$T/obj"; run "rm $T/obj"
grep -q '^\[ok\]' "$T/out" || { echo "FALHOU: teste destrutivo deveria dar ok: $(cat "$T/out")"; exit 1; }
echo VERIFY_CHK_ONCE_OK
