#!/usr/bin/env python3
"""Gera docs/report/bench/docker-vs-podman.png a partir dos .kv (requer matplotlib). Uso: chart.py [dir]"""
import glob, os, statistics, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "report", "bench")
def load(pattern):
    out = {"docker": [], "podman": []}
    for f in sorted(glob.glob(os.path.join(D, pattern))):
        kv = dict(l.strip().split("=", 1) for l in open(f) if "=" in l)
        if kv.get("done") == "1": out[kv["engine"]].append(kv)
    return out
full, cold = load("*-r[0-9].kv"), load("cold-*.kv")
def vals(src, eng, key): return [float(r[key]) for r in src[eng] if key in r]
def stat(v): return (statistics.mean(v), min(v), max(v))
def total_mem(eng):  # memoria real dos containers + processos auxiliares + daemon parado (0 containers)
    return [float(r["mem_idle_anon_mb"]) + float(r["overhead_procs_mb"]) + (statistics.mean(vals(cold, eng, "daemon_idle_zero_containers_mb")) if eng == "docker" else 0) for r in full[eng]]
def overhead(eng):
    return [float(r["overhead_procs_mb"]) + (statistics.mean(vals(cold, eng, "daemon_idle_zero_containers_mb")) if eng == "docker" else 0) for r in full[eng]]
P = [  # titulo, dados por motor (lista de amostras), formato, "menor e melhor"
    ("Subir a stack até tudo healthy", {e: vals(full, e, "start_to_healthy_s") for e in full}, "{:.0f} s"),
    ("Carregar as 4 imagens (offline, a frio)", {e: vals(cold, e, "image_load_cold_s") for e in cold}, "{:.0f} s"),
    ("Espaço em disco das imagens", {e: [v / 1024 for v in vals(cold, e, "image_store_mb")] for e in cold}, "{:.1f} GB"),
    ("Memória em repouso (containers + motor)", {e: [v / 1024 for v in total_mem(e)] for e in full}, "{:.2f} GB"),
    ("Custo do próprio motor (daemon + shims)", {e: overhead(e) for e in full}, "{:.0f} MB"),
    ("Crash do Graylog até voltar healthy", {e: vals(full, e, "recover_healthy_s") for e in full}, "{:.1f} s"),
]
SURF, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e3e2dd"
COL = {"docker": "#2a78d6", "podman": "#eb6834"}; NOME = {"docker": "Docker 29", "podman": "Podman 5.8"}
plt.rcParams.update({"font.family": "DejaVu Sans", "figure.facecolor": SURF, "axes.facecolor": SURF})
fig, axes = plt.subplots(2, 3, figsize=(16, 9.4), dpi=100)
fig.subplots_adjust(left=0.04, right=0.97, top=0.70, bottom=0.14, wspace=0.28, hspace=0.50)
for ax, (title, data, fmt) in zip(axes.flat, P):
    ymax = max(stat(data[e])[2] for e in data) * 1.0
    for i, e in enumerate(("docker", "podman")):
        m, lo, hi = stat(data[e])
        ax.barh(i, m, height=0.42, color=COL[e], zorder=2)
        if hi > lo:
            ax.plot([lo, hi], [i, i], color=INK, lw=1.8, zorder=3, solid_capstyle="butt")
            for x in (lo, hi): ax.plot([x, x], [i - 0.12, i + 0.12], color=INK, lw=1.8, zorder=3)
        ax.text(max(hi, m) + ymax * 0.03, i, fmt.format(m) + ("" if hi == lo else ""), va="center", ha="left", fontsize=15, color=INK, fontweight="bold")
    ax.set_xlim(0, ymax * 1.38); ax.set_ylim(1.6, -0.6); ax.set_yticks([])
    ax.set_title(title, loc="left", fontsize=14, color=INK, pad=12, fontweight="bold")
    ax.xaxis.set_visible(False)
    for s in ax.spines.values(): s.set_visible(False)
    ax.grid(axis="x", color=GRID, lw=0.8, zorder=0)
fig.text(0.04, 0.93, "Docker vs Podman rodando a mesma stack de logs", fontsize=26, fontweight="bold", color=INK, ha="left")
fig.text(0.04, 0.885, "Graylog 7.1 + OpenSearch 2.19 + MongoDB 7.0 · mesmo host, mesmas imagens, mesmo docker-compose.yml, mesma carga (2.500 msg/s por 5 min)", fontsize=14, color=INK2, ha="left")
fig.text(0.04, 0.845, "Barra = média de 2 rodadas; risco preto = mínimo e máximo. Menor é melhor em todos os gráficos.", fontsize=12.5, color=INK2, ha="left")
for k, e in enumerate(("docker", "podman")):  # legenda direta
    fig.patches.append(plt.Rectangle((0.04 + k * 0.13, 0.775), 0.012, 0.024, transform=fig.transFigure, color=COL[e]))
    fig.text(0.057 + k * 0.13, 0.787, NOME[e], fontsize=15, color=INK, va="center", fontweight="bold")
fig.text(0.04, 0.055, "Empate (sem diferença mensurável): CPU sob carga (0,6 núcleo nos dois) · logs recebidos (TCP 100%, UDP ~93–94%) · recuperação de crash (16 s).", fontsize=13, color=INK, ha="left")
fig.text(0.04, 0.025, "Podman rootful via docker compose no socket do Podman. Docker 29 usa o image store do containerd. Servidor compartilhado, 2 rodadas por motor: indicativo, não definitivo.", fontsize=11, color=INK2, ha="left")
out = os.path.join(D, "docker-vs-podman.png"); fig.savefig(out, facecolor=SURF); print(out)
