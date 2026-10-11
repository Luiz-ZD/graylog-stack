#!/usr/bin/env bash
# Sobe um bucket S3 de teste (rclone serve s3) e o override do exportador para usá-lo. Uso: s3up.sh up|down
set -euo pipefail
LAB="${LAB:-/tmp/graylog-lab}"
IMG=graylog-exporter:lab
case "${1:-}" in
  up)
    docker network create graylog-lab-e2e >/dev/null 2>&1 || true
    mkdir -p "$LAB/s3data/bucket-lab"; chmod 777 "$LAB/s3data" "$LAB/s3data/bucket-lab"
    docker rm -f lab-s3 >/dev/null 2>&1 || true
    docker run -d --name lab-s3 --network graylog-lab-e2e --restart unless-stopped -v "$LAB/s3data:/data" --entrypoint rclone "$IMG" \
      serve s3 /data --addr :9000 --auth-key labuser,labpass12345 >/dev/null
    cat > "$LAB/etc/rclone-s3.conf" <<EOC
[oci]
type = s3
provider = Other
access_key_id = labuser
secret_access_key = labpass12345
endpoint = http://lab-s3:9000
force_path_style = true
EOC
    cat > "$LAB/etc/override.yml" <<EOC
services:
  exporter:
    environment:
      EXPORT_ENABLED: "true"
      RCLONE_CONF_OVERRIDE: /run/override.conf
      OCI_BUCKET: bucket-lab
      OCI_PREFIX: logs/
    volumes:
      - "$LAB/etc/rclone-s3.conf:/run/override.conf:ro"
    networks: [internal, e2e]
networks:
  e2e: { external: true, name: graylog-lab-e2e }
EOC
    sed -i "s/^EXPORT_ENABLED=.*/EXPORT_ENABLED=true/" "$LAB/etc/stack.env"
    "$(dirname "$0")/lab.sh" up exporter ;;
  down) docker rm -f lab-s3 >/dev/null 2>&1 || true; rm -f "$LAB/etc/override.yml"; docker network rm graylog-lab-e2e >/dev/null 2>&1 || true ;;
esac
