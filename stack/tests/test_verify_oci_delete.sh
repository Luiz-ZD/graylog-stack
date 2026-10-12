#!/usr/bin/env bash
# verify.sh --oci: falta de permissao para APAGAR o objeto de teste nao e falha (o exportador so grava/le); deve avisar e dizer o nome.
set -uo pipefail
V="$(cd "$(dirname "$0")/.." && pwd)/scripts/verify.sh"
grep -q 'chk "OCI: apagar objeto de teste"' "$V" && { echo "FALHOU: apagar ainda e tratado como falha (chk)"; exit 1; }
grep -q 'NAO impede o exportador' "$V" || { echo "FALHOU: aviso de permissao de apagar ausente"; exit 1; }
grep -q 'Remova manualmente' "$V" || { echo "FALHOU: o aviso deve dizer o nome do objeto para remocao manual"; exit 1; }
bash -n "$V" || { echo "FALHOU: sintaxe"; exit 1; }
echo VERIFY_OCI_DELETE_OK
