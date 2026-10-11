#!/usr/bin/env bash
# Contrato de rede: só 9000/tcp, 3514/tcp, 4514/udp publicadas; Mongo/OpenSearch não.
set -u; f=0
curl -fs http://127.0.0.1:9000/api/system/lbstatus | grep -qi alive || { echo "FALHOU: lbstatus"; f=1; }
for p in "tcp 9000" "tcp 3514" "udp 4514"; do set -- $p; ss -${1:0:1}lnH | grep -qE ":$2\b" || { echo "FALHOU: $p"; f=1; }; done
ss -tlnH | grep -qE ':(27017|9200|9300)\b' && { echo "FALHOU: porta interna publicada"; f=1; }
[ $f = 0 ] && echo NETWORK_OK; exit $f
