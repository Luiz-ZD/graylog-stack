# Funcoes compartilhadas do install.sh. write_stack_env ENVF VERSIONS_ENV
# - regenera a cada execucao tudo que vem do install.conf e do versions.env (imagens do bundle)
# - preserva segredos (Mongo, password secret, hash do admin) e o estado de EXPORT_ENABLED (dono: `graylog-stack export on|off`)
# - define NEW_ADMIN_PASSWORD apenas quando gera um segredo novo do admin
write_stack_env() {
  local envf="$1" ver="$2" mongo="" secret="" sha="" exp="" tmp
  : "${WATCHDOG_IDLE_CHECK:=true}"   # install.conf antigo pode nao ter o parametro
  if [ -f "$envf" ]; then
    mongo=$(sed -n 's/^MONGO_PASSWORD=//p' "$envf"); secret=$(sed -n 's/^GRAYLOG_PASSWORD_SECRET=//p' "$envf")
    sha=$(sed -n 's/^GRAYLOG_ROOT_PASSWORD_SHA2=//p' "$envf"); exp=$(sed -n "s/^EXPORT_ENABLED='\\?\\([a-z]*\\)'\\?\$/\\1/p" "$envf")
  fi
  local bad
  for k in TZ HOST_IP GL_HEAP OS_HEAP PORT_HTTP PORT_WIN PORT_LIN EXPORT_ENABLED OCI_NAMESPACE OCI_BUCKET OCI_PREFIX OCI_REGION OCI_COMPARTMENT OCI_PROFILE EXPORT_FILTER EXPORT_EXCLUDE_SOURCES WATCHDOG_THRESHOLD_MIN WATCHDOG_IDLE_CHECK; do
    case "${!k}" in *"'"*) echo "[ERRO] $k no install.conf contém aspa simples ('), o que corromperia o stack.env" >&2; return 1;; esac
  done
  [ -n "$mongo" ] || mongo=$(openssl rand -hex 16)
  [ -n "$secret" ] || secret=$(openssl rand -hex 48)
  NEW_ADMIN_PASSWORD=""
  if [ -z "$sha" ]; then
    NEW_ADMIN_PASSWORD="$(openssl rand -base64 18 | tr -d '/+=')"; sha=$(printf %s "$NEW_ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1)
  fi
  [ -n "$exp" ] && EXPORT_ENABLED="$exp"
  tmp="$(mktemp "$envf.XXXXXX" 2>/dev/null || mktemp)"; chmod 600 "$tmp"
  {
    grep -v '^#' "$ver"
    echo "STACK_VAR=$STACK_VAR"; echo "STACK_ETC=$STACK_ETC"
    local k
    for k in TZ HOST_IP GL_HEAP OS_HEAP PORT_HTTP PORT_WIN PORT_LIN EXPORT_ENABLED OCI_NAMESPACE OCI_BUCKET OCI_PREFIX OCI_REGION OCI_COMPARTMENT OCI_PROFILE EXPORT_FILTER EXPORT_EXCLUDE_SOURCES WATCHDOG_THRESHOLD_MIN WATCHDOG_IDLE_CHECK; do
      printf "%s='%s'\n" "$k" "${!k}"
    done
    echo "MONGO_PASSWORD=$mongo"; echo "GRAYLOG_PASSWORD_SECRET=$secret"; echo "GRAYLOG_ROOT_PASSWORD_SHA2=$sha"
    grep -q '^EXPORTER_IMAGE=' "$ver" || echo "EXPORTER_IMAGE=graylog-exporter:bundle"
  } > "$tmp"
  mv "$tmp" "$envf"; chmod 600 "$envf"
}
