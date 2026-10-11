# Design (resumo público)

Ver `README.md`. Pipeline do exportador, por minuto:

1. `fetch(janela)` → API de exportação de mensagens do Graylog (`/api/views/search/messages`, CSV), com `gl2_receive_timestamp:[início TO fim}` (fim exclusivo), filtro configurável e `timerange` larga (a seleção real é pelo recebimento).
2. Normaliza `timestamp` para UTC (`...000Z`), ordena e grava `levels_0_a_3_AAAAMMDD_HHMMSS.csv` no `spool/` (atômico).
3. Avança o checkpoint.
4. Envia todo o `spool/` (mais antigo primeiro), verifica tamanho/MD5 no destino, registra no `ledger.jsonl` e apaga o arquivo local.

Janela fechada = `agora − 1 min` (folga para indexação); janelas perdidas são recuperadas a partir do checkpoint (limite configurável).
