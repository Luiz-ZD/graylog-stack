#!/usr/bin/env bash
# Calibra o EXPORT_FILTER: mostra exatamente o que o filtro envia (tipos que mais se repetem = candidatos a lixo)
# e o que ficou de fora com cara de importante. Le do Graylog (o bucket pode ser esvaziado por outra rotina).
# Uso: [TOPN=25] [SO_A=1] scripts/analisa-filtro.sh [MINUTOS]   (padrao 60; SO_A=1 mostra so o que o export envia)
ETC=${ETC:-/etc/graylog-stack}; MIN=${1:-60}
. "$ETC/stack.env"
ADMPW=$(cat "$ETC/admin-password" 2>/dev/null || sed -n "s/^ADMIN_PASSWORD=//p" "$ETC/stack.env")
FROM=$(date -u -d "-$MIN min" '+%Y-%m-%d %H:%M:%S.000'); TO=$(date -u '+%Y-%m-%d %H:%M:%S.000')
cat > /tmp/analisa.py <<'PY'
import csv, re, sys, collections
txt = open(sys.argv[1], newline='', errors='replace').read(); topn = int(sys.argv[2])
rows = [r for r in csv.reader(txt.splitlines(True)) if len(r) == 4 and r[0] != 'timestamp']
if not rows:
    print("0 mensagens" + ("" if (not txt.strip() or txt.strip().startswith('"timestamp"')) else "  [resposta: %s]" % txt[:150])); sys.exit()
tot = len(rows); win = [r for r in rows if 'AgentDevice=WindowsLog' in r[3]]
print("%d mensagens%s | Windows: %d (%.0f%%) | syslog: %d" % (tot, " (LIMITE de 20000 atingido: ha mais)" if tot >= 20000 else "", len(win), 100*len(win)/tot, tot-len(win)))
print("por level syslog:", dict(sorted(collections.Counter(r[2] for r in rows).items())))
def fld(m, k):
    x = re.search(r'\t%s=([^\t]*)' % k, m); return x.group(1) if x else ''
ids = collections.Counter(fld(r[3], 'EventID') for r in win if fld(r[3], 'EventID'))
if ids: print("EventID Windows (top 8):", dict(ids.most_common(8)))
sig = collections.Counter(); hosts = {}; ex = {}
for r in rows:
    m = r[3]
    if 'AgentDevice=WindowsLog' in m:
        s = "WIN %s | EventID=%s | Level=%s | %s" % (fld(m, 'Source')[:28], fld(m, 'EventID'), fld(m, 'Level'), re.sub(r'\d+', '#', fld(m, 'Message')[:60]))
    else:
        s = "SYS lvl=%s | %s" % (r[2], re.sub(r'[0-9a-f]{8,}|\d+', '#', m.split(' ', 1)[-1])[:90])
    sig[s] += 1; hosts.setdefault(s, set()).add(r[1]); ex.setdefault(s, m)
print("tipos distintos: %d | os %d mais repetidos:" % (len(sig), topn))
acc = 0
for s, n in sig.most_common(topn):
    acc += n
    print("  %5d  %4.1f%%  (acum %3.0f%%)  %2d hosts  %s" % (n, 100*n/tot, 100*acc/tot, len(hosts[s]), s[:140]))
    print("         ex: %s" % ex[s].replace('\t', ' | ')[:230])
print("hosts que mais enviam:", ", ".join("%s(%d)" % x for x in collections.Counter(r[1] for r in rows).most_common(6)))
PY
busca() { # $1 titulo, $2 consulta, $3 quantos tipos mostrar
  echo; echo "=================== $1 ==================="
  python3 - "$2" "$FROM" "$TO" > /tmp/q.json <<'PY'
import json, sys
q, fr, to = sys.argv[1:4]
print(json.dumps({"query_string": {"type": "elasticsearch", "query_string": 'gl2_receive_timestamp:["%s" TO "%s"] AND (%s)' % (fr, to, q)},
  "timerange": {"type": "absolute", "from": "2020-01-01T00:00:00.000Z", "to": "2031-01-01T00:00:00.000Z"},
  "streams": ["000000000000000000000001"], "fields_in_order": ["timestamp", "source", "level", "message"], "limit": 20000}))
PY
  curl -s -u "admin:$ADMPW" -H 'X-Requested-By: t' -H 'Content-Type: application/json' -H 'Accept: text/csv' -X POST "http://127.0.0.1:${PORT_HTTP:-9000}/api/views/search/messages" -d @/tmp/q.json > /tmp/qr.csv
  python3 /tmp/analisa.py /tmp/qr.csv "${3:-10}"
}
EXC=$(python3 -c "
import os
s=[x for x in os.environ.get('EXPORT_EXCLUDE_SOURCES','').split(',') if x]
print((' AND NOT (' + ' OR '.join('source:\"%s\"' % x.replace('\\\\','\\\\\\\\').replace('\"','\\\\\"') for x in s) + ')') if s else '')")
echo "Janela: ultimos $MIN min. Filtro atual do export: $EXPORT_FILTER $EXC"
busca "A) EXATAMENTE O QUE O EXPORT ENVIA (procure lixo: tipos que se repetem demais)" "($EXPORT_FILTER)$EXC" "${TOPN:-14}"
[ -n "${SO_A:-}" ] && exit 0
busca "B1) Linux/rede NAO exportado (nivel 4 a 7) com palavra de problema" 'NOT level:[0 TO 3] AND NOT message:"AgentDevice=WindowsLog" AND (message:failed OR message:failure OR message:denied OR message:"authentication failure" OR message:"invalid user" OR message:segfault OR message:"out of memory" OR message:panic OR message:fatal OR message:critical OR message:"i/o error" OR message:refused)' 14
busca "B2) Windows NAO exportado com EventID de seguranca importante (conta, grupo, bloqueio, log apagado, servico/tarefa nova, auditoria)" 'message:"AgentDevice=WindowsLog" AND NOT win_level:(Critical OR Error OR Warning) AND NOT win_event_type:16 AND (message:"EventID=4720" OR message:"EventID=4722" OR message:"EventID=4723" OR message:"EventID=4724" OR message:"EventID=4725" OR message:"EventID=4726" OR message:"EventID=4728" OR message:"EventID=4729" OR message:"EventID=4732" OR message:"EventID=4733" OR message:"EventID=4740" OR message:"EventID=4756" OR message:"EventID=4719" OR message:"EventID=1102" OR message:"EventID=4697" OR message:"EventID=4698" OR message:"EventID=7045" OR message:"EventID=4768" OR message:"EventID=4771" OR message:"EventID=4776")' 6
busca "B3) Linux/rede nivel 4 (warning): o que entraria se o filtro incluisse warning" 'level:4' 10
