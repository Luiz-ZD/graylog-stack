#!/bin/sh
set -e
if [ -n "$RCLONE_CONF_OVERRIDE" ]; then
  cp "$RCLONE_CONF_OVERRIDE" /run/rclone.conf
else
cat > /run/rclone.conf <<EOC
[oci]
type = oracleobjectstorage
provider = user_principal_auth
namespace = ${OCI_NAMESPACE}
compartment = ${OCI_COMPARTMENT}
region = ${OCI_REGION}
no_check_bucket = true
config_file = /etc/oci/config
config_profile = ${OCI_PROFILE:-DEFAULT}
${OCI_ENDPOINT:+endpoint = $OCI_ENDPOINT}
EOC
fi
chmod 600 /run/rclone.conf
mkdir -p "${STATE_DIR:-/data/state}" "${SPOOL_DIR:-/data/spool}"
exec "$@"
