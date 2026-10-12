#!/usr/bin/env python3
"""Agrega os .kv de ../../docs/report/bench e gera: tabela Markdown (comparativo.md) e dados para o grafico.
Uso: compare.py [diretorio]"""
import glob, os, statistics, sys, collections

d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "report", "bench")
runs = collections.defaultdict(list)
for f in sorted(glob.glob(os.path.join(d, "*-r*.kv"))):
    kv = dict(l.strip().split("=", 1) for l in open(f) if "=" in l)
    if kv.get("done") == "1":
        runs[kv["engine"]].append(kv)

def num(kv, k):
    try: return float(kv[k])
    except (KeyError, ValueError): return None

def agg(eng, k):
    v = [x for x in (num(r, k) for r in runs[eng]) if x is not None]
    return (statistics.mean(v), min(v), max(v)) if v else None

METRICS = [  # (chave, rotulo, unidade, menor-e-melhor)
    ("start_to_healthy_s", "Subir a stack até tudo *healthy*", "s", True),
    ("total_idle_mb", "Memória real em repouso (anon + processos do motor)", "MB", True),
    ("mem_idle_anon_mb", "  memória real dos 4 containers (anon)", "MB", True),
    ("mem_idle_file_mb", "  cache de arquivos dos 4 containers (recuperável)", "MB", True),
    ("overhead_procs_mb", "  processos do motor por container (shim/conmon/proxy)", "MB", True),
    ("daemon_marginal_mb", "  daemon do motor (variação com a stack no ar)", "MB", True),
    ("cpu_containers_cores", "CPU dos containers sob carga (2.500 msg/s)", "núcleos", True),
    ("cpu_engine_overhead_cores", "CPU do motor sob carga", "núcleos", True),
    ("mem_load_anon_mb", "Memória real dos containers sob carga", "MB", True),
    ("recover_restart_s", "Crash do Graylog: tempo até reiniciar", "s", True),
    ("recover_healthy_s", "Crash do Graylog: tempo até *healthy*", "s", True),
]
engines = [e for e in ("docker", "podman") if runs[e]]
out = ["| Métrica | " + " | ".join("%s (%d rodadas)" % (e.capitalize(), len(runs[e])) for e in engines) + " | Diferença |", "|---|" + "---|" * (len(engines) + 1)]
for k, label, unit, _ in METRICS:
    cells, means = [], []
    for e in engines:
        a = agg(e, k)
        cells.append("—" if a is None else ("%.1f %s" % (a[0], unit) if a[1] == a[2] else "%.1f %s (%.1f–%.1f)" % (a[0], unit, a[1], a[2])))
        means.append(None if a is None else a[0])
    diff = ""
    if len(means) == 2 and all(m is not None for m in means) and means[0]:
        diff = "%+.0f%%" % (100 * (means[1] - means[0]) / means[0]) if means[0] else ""
    out.append("| %s | %s | %s |" % (label, " | ".join(cells), diff))
# entrega de logs sob carga
for proto, key in (("TCP", "recv_tcp"), ("UDP", "recv_udp")):
    cells = []
    for e in engines:
        v = [(num(r, key), num(r, "sent_per_proto")) for r in runs[e] if num(r, key) is not None]
        cells.append("—" if not v else "%.1f%%" % (100 * statistics.mean(a / b for a, b in v)))
    out.append("| Logs recebidos sob carga (%s) | %s | |" % (proto, " | ".join(cells)))
open(os.path.join(d, "comparativo.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
print("\n".join(out))
