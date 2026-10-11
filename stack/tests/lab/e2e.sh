#!/usr/bin/env bash
# E2E: logs conhecidos -> Graylog -> exportador -> bucket S3 de teste. Imprime E2E_OK se tudo conferir.
set -uo pipefail
LAB="${LAB:-/tmp/graylog-lab}"
S="$(dirname "$0")/send_logs.py"; TAG="e2e$(date +%s)"; B="$LAB/s3data/bucket-lab/logs"
fail() { echo "FALHOU: $*"; exit 1; }
L() { python3 "$S" "$@" --tag "$TAG" >/dev/null; }
allcsv() { cat "$B"/levels_0_a_3_*.csv 2>/dev/null; }
udp() { python3 -c "import socket,sys;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.sendto(sys.argv[1].encode(),('127.0.0.1',4514))" "$1"; }
HDR() { date '+%b %e %H:%M:%S'; }

# --- Fase A: filtro. Esperados (7): linux<=3 x3, win Error x2, win Critical x1, win AuditFailure x1
L --kind linux --proto udp --count 3 --level 3 --src LAB-LIN-01
L --kind win --proto tcp --level 5 --count 2 --wlevel Error --etype 1 --src LAB-WIN-01
L --kind win --proto tcp --level 5 --count 1 --wlevel Critical --etype 1 --src LAB-WIN-02
L --kind win --proto tcp --level 5 --count 1 --wlevel Information --etype 16 --eid 4625 --src LAB-WIN-03
# ruido que NAO deve sair
L --kind linux --proto udp --count 5 --level 6 --src LAB-LIN-02
L --kind win --proto tcp --level 5 --count 4 --wlevel Information --etype 4 --src LAB-WIN-04
udp "<14>$(HDR) LAB-LIN-03 app: error error warning texto solto $TAG"
L --kind linux --proto udp --count 2 --level 2 --src EXCLUDED-HOST-01
# --- Fase B: fuso inclinado (timestamp 3h a frente do recebimento) -> deve sair 1 vez
udp "<11>$(date -d '+3 hours' '+%b %e %H:%M:%S') LAB-SKEW-01 app: skew $TAG"
# --- Fase C: fluxo continuo 1 msg/s por 150 s (todas level 3) -> 150 linhas, sem perda nem duplicata
python3 "$S" --kind linux --proto udp --count 150 --rate 1 --level 3 --src LAB-FLOW-01 --tag "flow$TAG" >/dev/null

echo "aguardando exportador (ate 6 min)..."
for i in $(seq 1 36); do
  A=$(allcsv | grep -c "$TAG" || true); F=$(allcsv | grep -c "message [0-9]*\"$" || true)
  FL=$(allcsv | grep -c "flow$TAG" || true)
  [ "$FL" -ge 150 ] && [ "$A" -ge 158 ] && break; sleep 10
done
echo "linhas com TAG=$A  fluxo=$FL"
N=$(allcsv | grep "$TAG" | grep -vc "flow$TAG" || true)
[ "$N" = 8 ] || fail "fase A+B: esperava 8 linhas (7 + 1 skew), obtive $N"
allcsv | grep -i 'texto solto' | grep -q "$TAG" && fail "ruido de texto solto exportado"
allcsv | grep "$TAG" | grep -q 'EXCLUDED-HOST-01' && fail "fonte excluida exportada"
[ "$(allcsv | grep -c "skew $TAG")" = 1 ] || fail "skew deve sair exatamente 1 vez"
[ "$FL" = 150 ] || fail "fluxo continuo: esperava 150, obtive $FL (perda ou duplicata nas viradas de janela)"
[ "$(allcsv | grep "flow$TAG" | sed 's/.*message \([0-9]*\)"$/\1/' | sort -n | uniq -d | wc -l)" = 0 ] || fail "duplicatas no fluxo"
F1=$(ls "$B"/levels_0_a_3_*.csv | head -1); head -1 "$F1" | grep -qx 'timestamp,source,level,message' || fail "cabecalho"
grep -qP '\r' "$F1" && fail "CR encontrado (esperado LF)"
head -2 "$F1" | tail -1 | grep -qE '^"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z","[^"]+",[0-9]+,".*"$' || fail "formato da linha"
echo E2E_OK
