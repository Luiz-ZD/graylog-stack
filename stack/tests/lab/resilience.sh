#!/usr/bin/env bash
# Casos R1..R10 contra o lab de desenvolvimento (projeto graylog-lab + bucket S3 de teste). Uso: resilience.sh [R1 R3 ...]  (padrao: todos)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LAB="${LAB:-/tmp/graylog-lab}"
B="$LAB/s3data/bucket-lab/logs"; ST="$LAB/var/export/state"; . "$LAB/etc/stack.env"
export STACK_ENV="$LAB/etc/stack.env" STACK_VAR="$LAB/var" STACK_ETC="$LAB/etc" COMPOSE_PROJECT=graylog-lab
WD="$HERE/../../scripts/watchdog.sh"; S="$HERE/send_logs.py"
OUT="${OUT:-$HERE/../../../docs/report/evidencias/resilience-$(date +%Y%m%d-%H%M).txt}"; mkdir -p "$(dirname "$OUT")"
res() { echo "$1 $2 — $3" | tee -a "$OUT"; }
allcsv() { cat "$B"/levels_0_a_3_*.csv 2>/dev/null; }
cnt() { allcsv | grep -c "$1" || true; }
waitcnt() { local t=$1 n=$2 max=${3:-360} i=0; while [ $i -lt $max ]; do [ "$(cnt "$t")" -ge "$n" ] && return 0; sleep 10; i=$((i+10)); done; return 1; }
send() { python3 "$S" --kind linux --proto udp --count "$1" --level 3 --src "${3:-LAB-RES}" --tag "$2" ${4:-} >/dev/null; }
healthy() { "$HERE/lab.sh" wait >/dev/null 2>&1; }
sj() { jq -r "$1" "$ST/status.json"; }
os() { docker exec graylog-lab-opensearch-1 curl -s "$@"; }
want() { [ $# -eq 0 ] && return 0; for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }
WANT=("$@"); run() { [ ${#WANT[@]} -eq 0 ] && return 0; for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }
echo "# Resiliencia $(date -Is)" > "$OUT"; healthy || { res SETUP FAIL "stack nao esta healthy"; exit 1; }

if run R1; then
  for svc in exporter mongodb opensearch graylog; do
    T="r1${svc:0:3}$(date +%s)"; kill -9 "$(docker inspect -f '{{.State.Pid}}' graylog-lab-$svc-1)"; sleep 5   # crash real (docker kill conta como parada manual)
    if healthy; then send 3 "$T"; waitcnt "$T" 3 420 && res R1-$svc PASS "kill -> volta healthy sozinho e logs voltam a ser ingeridos/exportados" || res R1-$svc FAIL "recuperou mas logs nao chegaram ao bucket"
    else res R1-$svc FAIL "nao voltou healthy"; fi
  done
fi
res R2 SKIP "reiniciar o daemon Docker derrubaria os demais containers desta maquina; politica de restart conferida: $(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' graylog-lab-graylog-1 graylog-lab-exporter-1 | tr '\n' ' ')"
if run R3; then
  T="r3$(date +%s)"; docker stop graylog-lab-exporter-1 >/dev/null
  python3 "$S" --kind linux --proto udp --count 120 --rate 1 --level 3 --src LAB-R3 --tag "$T" >/dev/null; sleep 120
  docker start graylog-lab-exporter-1 >/dev/null; healthy
  if waitcnt "$T" 120 420; then d=$(allcsv | grep "$T" | sed 's/.*message \([0-9]*\)"$/\1/' | sort -n | uniq -d | wc -l)
    [ "$(cnt "$T")" = 120 ] && [ "$d" = 0 ] && res R3 PASS "exportador parado ~4 min: 120/120 recuperados, 0 duplicatas" || res R3 FAIL "contagem=$(cnt "$T") dup=$d"
  else res R3 FAIL "so $(cnt "$T")/120 apos religar"; fi
fi
if run R4; then
  T="r4$(date +%s)"; docker stop lab-s3 >/dev/null; send 30 "$T" LAB-R4; sleep 200
  sc=$(sj .spool_count); "$WD" >/dev/null 2>&1; w=$?
  docker start lab-s3 >/dev/null; waitcnt "$T" 30 300; ok1=$?; sleep 70; sc2=$(sj .spool_count); "$WD" >/dev/null 2>&1; w2=$?
  [ "${sc:-0}" -ge 1 ] && [ $w -ne 0 ] && [ $ok1 -eq 0 ] && [ "$sc2" = 0 ] && [ $w2 -eq 0 ] && res R4 PASS "bucket fora: spool=$sc, vigia falhou; apos religar: 30/30 no bucket, spool=0, vigia ok" || res R4 FAIL "spool=$sc wd=$w ok=$ok1 spool_depois=$sc2 wd_depois=$w2"
fi
if run R5; then
  f=$(ls "$B"/levels_0_a_3_*.csv | head -1); n=$(basename "$f"); m1=$(md5sum "$f" | cut -d' ' -f1); c1=$(ls "$B"/levels_0_a_3_*.csv | wc -l)
  kill -9 "$(docker inspect -f '{{.State.Pid}}' graylog-lab-exporter-1)"; sleep 3; cp "$f" "$LAB/var/export/spool/$n"; healthy; sleep 80
  m2=$(md5sum "$B/$n" | cut -d' ' -f1); c2=$(ls "$B"/levels_0_a_3_*.csv | wc -l); left=$(ls "$LAB/var/export/spool" | wc -l)
  [ "$m1" = "$m2" ] && [ "$c1" = "$c2" ] && [ "$left" = 0 ] && res R5 PASS "arquivo ja enviado reaparece no spool apos crash: reenviado sobrescrevendo, sem objeto extra, spool vazio" || res R5 FAIL "md5 $m1/$m2 objetos $c1/$c2 spool=$left"
fi
if run R6; then
  T="r6$(date +%s)"; send 10 "$T" LAB-R6; docker stop graylog-lab-graylog-1 >/dev/null; sleep 60; cp1=$(sj .checkpoint); e1=$(sj '.last_error // ""'); sleep 120; cp2=$(sj .checkpoint)
  docker start graylog-lab-graylog-1 >/dev/null; healthy
  if waitcnt "$T" 10 420; then sleep 90; e2=$(sj '.last_error // ""')
    [[ "$e1" == graylog:* ]] && [ "$cp1" = "$cp2" ] && [ -z "$e2" ] && [ "$(cnt "$T")" = 10 ] && res R6 PASS "graylog fora 3 min: erro registrado, checkpoint parado em $cp1, depois recuperou 10/10 sem duplicar" || res R6 FAIL "e1='$e1' cp $cp1/$cp2 e2='$e2' n=$(cnt "$T")"
  else res R6 FAIL "nao recuperou: $(cnt "$T")/10"; fi
fi
if run R9; then
  for c in "" lixo; do printf '%s' "$c" > "$ST/checkpoint"; sleep 75; done; rm -f "$ST/checkpoint"; sleep 75
  n=$(grep -c checkpoint_reset "$ST/ledger.jsonl"); e=$(sj '.last_error // ""')
  [ "$n" -ge 3 ] && [ -z "$e" ] && [ -s "$ST/checkpoint" ] && res R9 PASS "checkpoint vazio/corrompido/ausente: $n reinicios registrados, sem travar, checkpoint refeito" || res R9 FAIL "resets=$n erro='$e'"
fi
if run R10; then
  bad=$(allcsv | grep -vE '^timestamp,source,level,message$' | grep -cvE '^"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z","[^"]*",[0-9]*,".*"$' || true)
  [ "$bad" = 0 ] && ! grep -lP '\r' "$B"/levels_0_a_3_*.csv >/dev/null 2>&1 && res R10 PASS "todas as linhas de $(ls "$B"/levels_0_a_3_*.csv | wc -l) arquivos no formato jq @csv; LF; cabecalho exato" || res R10 FAIL "$bad linhas fora do formato"
fi
if run R7; then
  OLD=$(os 'localhost:9200/graylog_*/_count?q=source:LAB-LOAD-TCP*' | jq .count); OLU=$(os 'localhost:9200/graylog_*/_count?q=source:LAB-LOAD-UDP*' | jq .count)
  ( python3 "$S" --kind linux --proto tcp --count 750000 --rate 1250 --level 6 --src LAB-LOAD-TCP --tag load >/dev/null & python3 "$S" --host "$(hostname -I | awk '{print $1}')" --kind linux --proto udp --count 750000 --rate 1250 --level 6 --src LAB-LOAD-UDP --tag load >/dev/null; wait )
  sleep 90; os -XPOST 'localhost:9200/graylog_*/_refresh' >/dev/null
  NT=$(os 'localhost:9200/graylog_*/_count?q=source:LAB-LOAD-TCP*' | jq .count); NU=$(os 'localhost:9200/graylog_*/_count?q=source:LAB-LOAD-UDP*' | jq .count)
  rt=$((NT-OLD)); ru=$((NU-OLU)); stats=$(docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' | grep graylog-lab | tr '\n' ';')
  [ "$rt" = 750000 ] && res R7 PASS "10 min a 2500 msg/s: TCP $rt/750000 (0 perda), UDP $ru/750000 ($((100*ru/750000))%); $stats" || res R7 FAIL "TCP $rt/750000 UDP $ru/750000; $stats"
  echo "$stats" > "$HERE/../../../docs/report/evidencias/stats-load.txt"
fi
if run R8; then
  . "$LAB/etc/stack.env"; A="admin:$ADMIN_PASSWORD"; U=http://127.0.0.1:9000/api
  SET=$(curl -s -u "$A" "$U/system/indices/index_sets" | jq -c '.index_sets[]|select(.default)'); ID=$(echo "$SET" | jq -r .id)
  curl -s -u "$A" -H 'X-Requested-By: t' -H 'Content-Type: application/json' -X PUT "$U/system/indices/index_sets/$ID" -d "$(echo "$SET" | jq -c '.rotation_strategy.max_size=20971520')" >/dev/null
  python3 "$S" --kind linux --proto tcp --count 600000 --level 6 --src LAB-RET --tag ret >/dev/null; sleep 60
  n=$(os 'localhost:9200/_cat/indices/graylog_*?h=index' | grep -c graylog_); 
  curl -s -u "$A" -H 'X-Requested-By: t' -H 'Content-Type: application/json' -X PUT "$U/system/indices/index_sets/$ID" -d "$SET" >/dev/null
  [ "$n" -le 10 ] && [ "$n" -ge 2 ] && res R8 PASS "rotacao por tamanho (20 MB no teste) com retencao: $n indices graylog_* (<=10); config de 1 GB restaurada" || res R8 FAIL "$n indices"
fi
echo "FIM $(date -Is)" | tee -a "$OUT"
