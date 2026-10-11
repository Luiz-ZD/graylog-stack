#!/usr/bin/env bash
# Bordas: (1) rajada de 30.000 msgs em segundos nao pode ser truncada; (2) timestamps muito fora do relogio (+-40 dias) saem 1 vez.
set -uo pipefail
LAB="${LAB:-/tmp/graylog-lab}"
S="$(dirname "$0")/send_logs.py"; TAG="edge$(date +%s)"; B="$LAB/s3data/bucket-lab/logs"
fail() { echo "FALHOU: $*"; exit 1; }
allcsv() { cat "$B"/levels_0_a_3_*.csv 2>/dev/null; }
udp() { python3 -c "import socket,sys;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.sendto(sys.argv[1].encode(),('127.0.0.1',4514))" "$1"; }
python3 "$S" --kind linux --proto tcp --count 30000 --level 3 --src LAB-BURST --tag "burst$TAG" >/dev/null
udp "<11>$(date -d '+40 days' '+%b %e %H:%M:%S') LAB-FUT-01 app: futuro $TAG"
udp "<11>$(date -d '-40 days' '+%b %e %H:%M:%S') LAB-PAST-01 app: passado $TAG"
udp "<11>$(date '+%b %e %H:%M:%S') =HEQ$TAG =cmd"; udp "<11>$(date '+%b %e %H:%M:%S') +HPL$TAG +x"; udp "<11>$(date '+%b %e %H:%M:%S') -HMI$TAG -x"; udp "<11>$(date '+%b %e %H:%M:%S') @HAT$TAG @x"
echo "aguardando exportador (ate 6 min)..."
for i in $(seq 1 36); do
  b=$(allcsv | grep -c "burst$TAG"); f=$(allcsv | grep -c "futuro $TAG"); p=$(allcsv | grep -c "passado $TAG")
  [ "$b" -ge 30000 ] && [ "$f" -ge 1 ] && [ "$p" -ge 1 ] && [ "$(allcsv | grep -cE "(=HEQ|\+HPL|-HMI|@HAT)$TAG")" -ge 4 ] && break; sleep 10
done
echo "rajada=$b/30000 futuro=$f passado=$p"
[ "$b" = 30000 ] || fail "rajada truncada ou duplicada: $b/30000"
[ "$f" = 1 ] || fail "timestamp +40 dias: $f (esperado 1)"
[ "$p" = 1 ] || fail "timestamp -40 dias: $p (esperado 1)"
A=$(allcsv)   # (sem pipe com grep -q: com pipefail o SIGPIPE do cat daria falso negativo)
for c in "=HEQ" "+HPL" "-HMI" "@HAT"; do grep -qF ",\"$c$TAG\",3,\"$c$TAG " <<<"$A" || fail "valor iniciado por ${c:0:1} deve sair sem prefixo de formula"; done
echo EDGE_OK
