#!/usr/bin/env bash
# Monta build/graylog-bundle-AAAAMMDD.tar.gz (imagens, compose, scripts, rpms, rclone fixado). Requer internet (só aqui, nunca no cliente).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; BUILD="$ROOT/../build"; D="$(date +%Y%m%d)"; B="$BUILD/graylog-bundle-$D"
. "$ROOT/versions.env"
tagof(){ sed -n "s/^# $1 tag=//p" "$ROOT/versions.env"; }
[ -d "$BUILD/docker-rpms-src" ] || { echo "rode antes: scripts/build-rpms.sh"; exit 1; }
rm -rf -- "$B" && mkdir -p "$B/images"
# rclone fixado + checksum
RC="$BUILD/rclone-$RCLONE_VERSION"; mkdir -p "$RC"
if [ ! -x "$RC/rclone" ]; then
  curl -fsSL "https://downloads.rclone.org/$RCLONE_VERSION/rclone-$RCLONE_VERSION-linux-amd64.zip" -o "$RC/r.zip"
  curl -fsSL "https://downloads.rclone.org/$RCLONE_VERSION/SHA256SUMS" -o "$RC/SUMS"
  want="$(grep "rclone-$RCLONE_VERSION-linux-amd64.zip" "$RC/SUMS" | awk '{print $1}' | tail -1)"; got="$(sha256sum "$RC/r.zip" | awk '{print $1}')"
  [ -n "$want" ] && [ "$want" = "$got" ] || { echo "checksum do rclone NÃO confere"; exit 1; }
  python3 -I -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1]);n=[x for x in z.namelist() if x.endswith('/rclone')][0];open(sys.argv[2],'wb').write(z.read(n))" "$RC/r.zip" "$RC/rclone"; chmod +x "$RC/rclone"
fi
cp "$RC/rclone" "$ROOT/exporter/rclone"
EXP="graylog-bundle/exporter:$D"
docker build -q --build-arg PYTHON_IMAGE="$PYTHON_IMAGE" -t "$EXP" "$ROOT/exporter" >/dev/null
# tags locais ligadas aos digests fixados; IDs gravados para conferência na instalação
: > "$B/images/IMAGE_IDS"
for n in graylog opensearch mongo; do
  var="$(echo $n | tr a-z A-Z)_IMAGE"; ref="graylog-bundle/$n:$(tagof $n)"; docker tag "${!var}" "$ref"
  docker save "$ref" -o "$B/images/$n.tar"; echo "$ref $(docker image inspect -f '{{.Id}}' "$ref")" >> "$B/images/IMAGE_IDS"
done
docker save "$EXP" -o "$B/images/exporter.tar"; echo "$EXP $(docker image inspect -f '{{.Id}}' "$EXP")" >> "$B/images/IMAGE_IDS"
cat > "$B/versions.env" <<EOV
GRAYLOG_IMAGE=graylog-bundle/graylog:$(tagof graylog)
OPENSEARCH_IMAGE=graylog-bundle/opensearch:$(tagof opensearch)
MONGO_IMAGE=graylog-bundle/mongo:$(tagof mongo)
EXPORTER_IMAGE=$EXP
RCLONE_VERSION=$RCLONE_VERSION
EOV
cp -a "$ROOT"/{docker-compose.yml,install.conf.example,scripts,provision,systemd} "$B/"; cp -a "$BUILD/docker-rpms-src" "$B/docker-rpms"
rm -f -- "$B/scripts/build-bundle.sh" "$B/scripts/build-rpms.sh"
cat > "$B/README.txt" <<EOR
Bundle Graylog ($D) — instalação 100% offline
1) cp install.conf.example install.conf   e preencha (IP, NTP_SERVERS, bucket OCI, caminhos do ~/.oci/config e da chave)
2) scripts/install.sh --dry-run            (confere o ambiente e mostra a transação de pacotes; não altera nada)
3) scripts/install.sh
4) scripts/verify.sh --oci                 (smoke test do bucket: grava, lê e apaga um objeto)
Corte:  graylog-stack export on    Estado: graylog-stack status    Prova de envio: graylog-stack proof 10
EOR
( cd "$B" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS )
tar -C "$BUILD" -czf "$BUILD/graylog-bundle-$D.tar.gz" "graylog-bundle-$D"
ls -lh "$BUILD/graylog-bundle-$D.tar.gz"; du -sh "$B"
