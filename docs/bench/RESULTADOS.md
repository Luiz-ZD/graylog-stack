# Docker vs Podman rodando a mesma stack de logs

**Stack:** Graylog 7.1.10 + OpenSearch 2.19.6 + MongoDB 7.0.43 + exportador (4 containers), o mesmo `docker-compose.yml` e o mesmo bundle de imagens (carregado do `.tar`, sem rede).
**Motores:** Docker 29 (image store do containerd) e Podman 5.8.2 (*rootful*, crun + netavark), um de cada vez, na mesma máquina (AlmaLinux 9.8, 4 vCPU, 15 GB), que roda outros 15 containers de outros projetos.
**Orquestração idêntica:** o `docker compose` v5 fala com o Docker e, apontado para o socket de API do Podman, com o Podman. **O mesmo arquivo Compose rodou nos dois sem nenhuma alteração.**
**Carga:** 2.500 msg/s (1.250 TCP + 1.250 UDP, syslog) por 5 minutos, enviada pelo IP do host (caminho real, DNAT). Heaps de 1 GB (Graylog e OpenSearch). Ordem das rodadas: Docker, Podman, Podman, Docker, para cancelar efeito de ordem.

## Resultados (média de 2 rodadas; entre parênteses, mínimo–máximo)

| Métrica | Docker 29 | Podman 5.8 | Diferença |
|---|---|---|---|
| Subir a stack até tudo *healthy* | 58,1 s (57,8–58,4) | 72,8 s (64,2–81,4) | Podman +25% (6 a 23 s mais lento) |
| Carregar as 4 imagens, a frio, offline | 43,7 s (43,5–43,9) | 46,7 s (45,7–47,6) | Podman +7% |
| Espaço em disco das imagens | 4.911 MB | 3.116 MB | **Podman −37%** |
| Daemon do motor, parado, sem containers | **112 MB** (111–114) | **0** (não há daemon) | — |
| Processos auxiliares por container (shim, proxy / conmon) | 39 MB | 2 MB | Podman −95% |
| Custo total do motor para esta stack | ~152 MB | ~2 MB | **Podman ~150 MB menor** |
| Memória real dos 4 containers em repouso (`anon`) | 2.432 MB (2.376–2.487) | 2.559 MB (2.440–2.677) | **sem diferença mensurável** (faixas se sobrepõem) |
| Memória em repouso, containers + motor | 2,52 GB | 2,50 GB | empate |
| Cache de arquivos dos containers (recuperável) | 625 MB | 219 MB | Docker carrega ~400 MB a mais de cache |
| CPU dos containers sob carga | 0,6 núcleo | 0,6 núcleo | **empate** |
| Logs recebidos sob carga (TCP / UDP) | 100% / 93,2% | 100% / 93,8% | **empate** |
| Crash do Graylog (`kill -9`) até voltar *healthy* | 16,4 s | 16,6 s | **empate** |
| Limite padrão de arquivos abertos no container | 1.024 | 1.048.576 | diferença de padrão |

Gráfico: `docker-vs-podman.png`. Dados brutos: `*.kv` (uma chave por linha). Reprodução: `stack/bench/` (`run-all.sh`, `run-cold.sh`, `compare.py`, `chart.py`).

## O que isto diz (e o que não diz)
- **Para esta carga, o desempenho é equivalente:** mesma CPU, mesma entrega de logs, mesma recuperação de crash. Ninguém "ganha" por desempenho.
- **O que o Podman realmente economiza:** o daemon (~110 MB parado) e ~1,8 GB de disco de imagens, ao custo de **subir a stack um pouco mais devagar**. Em memória dos containers, **não** houve vantagem.
- **A "vantagem de memória" apareceu e sumiu:** a primeira medição mostrou o Podman ~10% menor. Era um artefato: eu medi o cgroup interno do Podman (que exclui o `conmon` e o cache de log) contra o cgroup completo do Docker (que inclui o shim). Corrigido o nível de medição e separando memória real (`anon`) de cache, a diferença desapareceu. Os resultados da primeira medição ficam em `rodada1-instrumento-antigo/` só como registro.
- A perda de ~6,5% no UDP aparece nos dois motores e vem do teste (um único emissor Python na mesma máquina), não do motor.

## Ressalvas
- **2 rodadas por motor** (11 minutos cada): é indicativo, não definitivo. Houve um desvio de 81 s no Podman (rodada 1) contra 64 s na rodada 2.
- Servidor **compartilhado** com outros containers; o daemon do Docker chegou a ~570 MB com os 15 containers do host, e o número "112 MB" é o do daemon **sem nenhum container** (motor isolado).
- Carga/disco das imagens medidos em **motores limpos e isolados** (segundo `dockerd` com containerd próprio; `podman --root` próprio). Sem isso o Docker reaproveitava camadas em cache e o número era inválido.
- O Docker 29 guarda as camadas duas vezes (blobs compactados + descompactados) no image store do containerd; com o *graphdriver* clássico (`overlay2`) o disco seria parecido com o do Podman.
- **Não medido:** Podman *rootless*; Quadlet/systemd (a forma "nativa" de rodar containers permanentes no Podman); SELinux em modo *enforcing*; persistência após reboot (com Compose, o Podman precisa do `podman-restart.service` para a política `restart` valer depois de reiniciar a máquina); comportamento ao reiniciar o daemon.
