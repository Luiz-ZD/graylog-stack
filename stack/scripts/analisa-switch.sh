#!/usr/bin/env bash
# Mostra o que os switches/equipamentos de rede enviam: o que VAI e o que NAO VAI para o bucket.
# Uso: [SW='regex dos nomes'] [EXCLUI='consulta'] bash /root/analisa-switch.sh [MINUTOS]   (padrao 20)
ETC=${ETC:-/etc/graylog-stack}; MIN=${1:-20}
PADRAO_SW='(^|[-_ .])(sw|switch|os[0-9]+|omni|core|fgt|fw|ap|wlc|rt|router)([-_ .0-9]|$)'; SW=${SW:-$PADRAO_SW}
. "$ETC/stack.env"
ADMPW=$(cat "$ETC/admin-password" 2>/dev/null || sed -n "s/^ADMIN_PASSWORD=//p" "$ETC/stack.env")
FROM=$(date -u -d "-$MIN min" '+%Y-%m-%d %H:%M:%S.000'); TO=$(date -u '+%Y-%m-%d %H:%M:%S.000')
busca() { # $1 consulta $2 arquivo
  python3 - "$1" "$FROM" "$TO" > /tmp/qs.json <<'PY'
import json, sys
q, fr, to = sys.argv[1:4]
print(json.dumps({"query_string": {"type": "elasticsearch", "query_string": 'gl2_receive_timestamp:["%s" TO "%s"] AND (%s)' % (fr, to, q)},
  "timerange": {"type": "absolute", "from": "2020-01-01T00:00:00.000Z", "to": "2031-01-01T00:00:00.000Z"},
  "streams": ["000000000000000000000001"], "fields_in_order": ["timestamp", "source", "level", "message"], "limit": 20000}))
PY
  curl -s -u "admin:$ADMPW" -H 'X-Requested-By: t' -H 'Content-Type: application/json' -H 'Accept: text/csv' -X POST "http://127.0.0.1:${PORT_HTTP:-9000}/api/views/search/messages" -d @/tmp/qs.json > "$2"
}
BASE='NOT message:"AgentDevice=WindowsLog"'${EXCLUI:+" AND NOT ($EXCLUI)"}   # EXCLUI='message:Fulano' tira da analise uma fonte muito barulhenta
busca "$BASE" /tmp/sw_all.csv
busca "$BASE AND ($EXPORT_FILTER)" /tmp/sw_exp.csv
echo "Janela: ultimos $MIN min | filtro do export: $EXPORT_FILTER"
SW="$SW" python3 - <<'PY'
import csv, os, re, collections
def rd(p):
    t = open(p, newline='', errors='replace').read()
    return [r for r in csv.reader(t.splitlines(True)) if len(r) == 4 and r[0] != 'timestamp']
allr, exp = rd('/tmp/sw_all.csv'), rd('/tmp/sw_exp.csv')
key = lambda r: (r[0], r[1], r[3])
ek = collections.Counter(key(r) for r in exp)
flag = []
for r in allr:
    k = key(r)
    if ek[k] > 0: ek[k] -= 1; flag.append(True)
    else: flag.append(False)
n = len(allr)
print("\n%d mensagens nao-Windows%s | vao para o bucket: %d (%.0f%%)" % (n, "  [LIMITE 20000: use janela menor]" if n >= 20000 else "", len(exp), 100*len(exp)/max(n,1)))
src = collections.Counter(r[1] for r in allr); se = collections.Counter(r[1] for r, f in zip(allr, flag) if f)
print("\n=== A) fontes que mais enviam (total / vao p/ bucket) ===")
for s, c in src.most_common(40): print("  %6d  %5d  %s" % (c, se[s], s))
rx = re.compile(os.environ['SW'], re.I)
sel = [s for s in src if rx.search(s)]
print("\n=== B) equipamentos de rede (nome casa com %s): %d fontes ===" % (os.environ['SW'], len(sel)))
def sig(m):
    body = m.split(' ', 1)[-1]
    return re.sub(r'\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b|\d+(?:\.\d+){3}|\d+', '#', body)[:100]
for s in sorted(sel, key=lambda x: -src[x]):
    rows = [(r, f) for r, f in zip(allr, flag) if r[1] == s]
    print("\n--- %s: %d msgs, %d vao p/ bucket | levels %s" % (s, len(rows), sum(f for _, f in rows), dict(sorted(collections.Counter(r[2] for r, _ in rows).items()))))
    c = collections.Counter(); fe = {}; ex = {}
    for r, f in rows:
        k = sig(r[3]); c[k] += 1; fe[k] = f; ex.setdefault(k, r[3])
    for k, v in c.most_common(10):
        print("   %5d  %s  %s" % (v, "BUCKET" if fe[k] else "fora  ", k))
        print("          ex: %s" % ex[k][:200])
PY
