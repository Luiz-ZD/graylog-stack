#!/usr/bin/env bash
# Valida o formato de config do rclone oracleobjectstorage (user_principal_auth + ~/.oci/config) contra um stub local.
# NAO valida IAM nem a assinatura real: isso fica para verify.sh --oci no cliente.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; T="$(mktemp -d)"; PORT=18081
python3 "$HERE/oci_stub.py" $PORT >/dev/null 2>&1 & SP=$!
trap 'kill $SP 2>/dev/null; rm -rf "$T"' EXIT
openssl genrsa -out "$T/key.pem" 2048 2>/dev/null; chmod 600 "$T/key.pem"
cat > "$T/oci_config" <<EOC
[DEFAULT]
user=ocid1.user.oc1..aaaaaaaatestuser
fingerprint=aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
tenancy=ocid1.tenancy.oc1..aaaaaaaatesttenancy
region=sa-saopaulo-1
key_file=$T/key.pem
EOC
cat > "$T/rclone.conf" <<EOC
[oci]
type = oracleobjectstorage
provider = user_principal_auth
namespace = nsx
compartment = ocid1.compartment.oc1..aaaaaaaatest
region = sa-saopaulo-1
no_check_bucket = true
config_file = $T/oci_config
config_profile = DEFAULT
endpoint = http://127.0.0.1:$PORT
EOC
sleep 1; printf 'timestamp,source,level,message\n"2026-10-11T18:00:00.000Z","H",3,"m"\n' > "$T/teste.csv"
timeout 60 rclone --config "$T/rclone.conf" copyto "$T/teste.csv" oci:bucket-teste/logs/teste.csv >/dev/null 2>&1 || { echo "FALHOU: rclone copyto"; exit 1; }
LOG="$(curl -s -m 5 localhost:$PORT/__log)"
echo "$LOG" | jq -e '[.[]|select(.m=="PUT" and .p=="/n/nsx/b/bucket-teste/o/logs/teste.csv" and (.auth|startswith("Signature")))]|length>=1' >/dev/null || { echo "FALHOU: PUT assinado no caminho esperado ausente"; echo "$LOG" | head -c 600; exit 1; }
echo "OCI_STUB_OK"
