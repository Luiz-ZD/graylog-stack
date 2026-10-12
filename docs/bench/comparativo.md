| Métrica | Docker (2 rodadas) | Podman (2 rodadas) | Diferença |
|---|---|---|---|
| Subir a stack até tudo *healthy* | 58.1 s (57.8–58.4) | 72.8 s (64.2–81.4) | +25% |
| Memória real em repouso (anon + processos do motor) | 2470.5 MB (2422.0–2519.0) | 2562.5 MB (2444.0–2681.0) | +4% |
|   memória real dos 4 containers (anon) | 2431.5 MB (2376.0–2487.0) | 2558.5 MB (2440.0–2677.0) | +5% |
|   cache de arquivos dos 4 containers (recuperável) | 625.0 MB (609.0–641.0) | 219.0 MB (211.0–227.0) | -65% |
|   processos do motor por container (shim/conmon/proxy) | 39.2 MB (32.0–46.4) | 1.9 MB | -95% |
|   daemon do motor (variação com a stack no ar) | -19.0 MB (-26.0–-12.0) | 1.5 MB (1.0–2.0) | -108% |
| CPU dos containers sob carga (2.500 msg/s) | 0.6 núcleos (0.6–0.6) | 0.6 núcleos (0.6–0.6) | +1% |
| CPU do motor sob carga | 0.0 núcleos | 0.0 núcleos | -100% |
| Memória real dos containers sob carga | 2820.5 MB (2783.0–2858.0) | 2931.0 MB (2925.0–2937.0) | +4% |
| Crash do Graylog: tempo até reiniciar | 0.8 s | 0.6 s (0.6–0.7) | -19% |
| Crash do Graylog: tempo até *healthy* | 16.4 s (16.3–16.4) | 16.6 s (16.5–16.6) | +1% |
| Logs recebidos sob carga (TCP) | 100.0% | 100.0% | |
| Logs recebidos sob carga (UDP) | 93.2% | 93.8% | |
