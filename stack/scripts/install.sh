#!/usr/bin/env bash
# Instala/atualiza a stack Graylog. Idempotente. Uso: install.sh [--dry-run] [--conf FILE] [--lab]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DRY=0; CONF="$HERE/install.conf"; LAB=0
while [ $# -gt 0 ]; do case "$1" in --dry-run) DRY=1;; --conf) CONF="$2"; shift;; --lab) LAB=1;; esac; shift; done
[ -f "$CONF" ] || { echo "[ERRO] $CONF não existe (copie install.conf.example)" >&2; exit 1; }
. "$CONF"
STACK_OPT="${STACK_OPT:-/opt/graylog-stack}"; STACK_ETC="${STACK_ETC:-/etc/graylog-stack}"; STACK_VAR="${STACK_VAR:-/var/lib/graylog-stack}"
P="${COMPOSE_PROJECT:-graylog-stack}"
ok(){ echo "[ok]   $*"; }; warn(){ echo "[aviso] $*"; }; die(){ echo "[ERRO] $*" >&2; exit 1; }
run(){ if [ "$DRY" = 1 ]; then echo "[dry]  $*"; else "$@"; fi; }

echo "== Pré-verificações =="
if [ -f "$HERE/SHA256SUMS" ]; then (cd "$HERE" && sha256sum -c --quiet SHA256SUMS) || die "SHA256SUMS não confere: bundle corrompido"; ok "integridade do bundle (SHA256SUMS)"; fi
[ "$LAB" = 1 ] || [ "$(id -u)" = 0 ] || die "rode como root"
if [ "$LAB" = 0 ]; then grep -q 'platform:el9' /etc/os-release 2>/dev/null && ok "RHEL 9" || warn "SO não é EL9"; fi
mkdir -p "$(dirname "$STACK_VAR")"
avail=$(df -BG --output=avail "$(dirname "$STACK_VAR")" | tail -1 | tr -dc 0-9); [ "$avail" -ge 30 ] || die "espaço livre ${avail}G < 30G"; ok "espaço livre ${avail}G"
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${P}-graylog-1$"; then
  for p in "$PORT_HTTP" "$PORT_WIN" "$PORT_LIN"; do ss -tulnH | awk '{print $5}' | grep -qE "[:.]$p$" && die "porta $p em uso"; done
fi; ok "portas $PORT_HTTP/$PORT_WIN/$PORT_LIN livres (ou já da stack)"
command -v getenforce >/dev/null && ok "SELinux: $(getenforce)"
for c in curl openssl python3 sha256sum; do command -v $c >/dev/null || die "comando ausente: $c"; done
if [ "$LAB" = 0 ]; then
  [ "$(timedatectl show -p Timezone --value)" = "$TZ" ] || die "fuso diferente de $TZ (timedatectl set-timezone $TZ)"
  if [ -n "${NTP_SERVERS:-}" ]; then
    for s in $NTP_SERVERS; do grep -q "^server $s" /etc/chrony.conf || run sed -i "1i server $s iburst" /etc/chrony.conf; done
    run systemctl enable --now chronyd; run systemctl restart chronyd; [ "$DRY" = 1 ] || sleep 5
  fi
  systemctl is-active --quiet chronyd || die "chronyd inativo; informe NTP_SERVERS em install.conf"
  chronyc waitsync 6 0.5 >/dev/null 2>&1 || warn "chrony ainda sem sincronismo; confira NTP_SERVERS"
  off=$(chronyc tracking | awk '/System time/{print $4}'); ok "desvio de relógio ${off}s"
  awk -v o="$off" 'BEGIN{exit !(o>2)}' && die "relógio desviado > 2 s; o OCI rejeita requisições assinadas"
fi
need_rpm=0; command -v jq >/dev/null || need_rpm=1; docker compose version >/dev/null 2>&1 || need_rpm=1
RPMS="docker-ce docker-ce-cli containerd.io docker-compose-plugin jq"
dnf_local(){ dnf -y --disablerepo='*' --repofrompath=graylog-bundle,"$HERE/docker-rpms" --setopt=graylog-bundle.gpgcheck=0 --setopt=install_weak_deps=False "$@"; }
if [ "$LAB" = 0 ] && [ $need_rpm = 1 ]; then
  [ -d "$HERE/docker-rpms/repodata" ] || die "Docker/jq ausentes e sem docker-rpms/ no bundle"
  echo "-- transação prevista (confira se não substitui pacotes do sistema além do necessário):"
  dnf_local --assumeno install $RPMS 2>&1 | sed -n '/Installing\|Upgrading\|Transaction Summary\|Problem\|nothing provides/,$p' | head -40 || true
  if [ "$DRY" = 0 ]; then dnf_local install $RPMS; systemctl enable --now docker; fi
fi
if [ "$DRY" = 1 ]; then echo "== dry-run concluído, nada foi alterado =="; exit 0; fi
docker compose version >/dev/null 2>&1 || die "Docker Compose indisponível"; command -v jq >/dev/null || die "jq ausente"; ok "docker $(docker --version | awk '{print $3}' | tr -d ,)"

echo "== Sistema =="
if [ "$LAB" = 0 ]; then
  printf 'vm.max_map_count=262144\nnet.core.rmem_max=16777216\nnet.core.rmem_default=8388608\n' > /etc/sysctl.d/99-graylog-stack.conf; sysctl --system >/dev/null; ok "sysctl aplicado"
fi
mkdir -p "$STACK_OPT" "$STACK_ETC/oci" "$STACK_VAR"/{mongo,opensearch,graylog,export/state,export/spool}; chmod 700 "$STACK_ETC"
chown -R 1000:1000 "$STACK_VAR/opensearch"; chown -R 1100:1100 "$STACK_VAR/graylog"; chown -R 999:999 "$STACK_VAR/mongo"
cp -a "$HERE/docker-compose.yml" "$HERE/scripts" "$HERE/provision" "$HERE/versions.env" "$STACK_OPT/"

echo "== Segredos e .env =="
ENVF="$STACK_ETC/stack.env"
. "$HERE/scripts/lib-env.sh"
write_stack_env "$ENVF" "$HERE/versions.env"
if [ -n "$NEW_ADMIN_PASSWORD" ]; then
  (umask 077; printf '%s\n' "$NEW_ADMIN_PASSWORD" > "$STACK_ETC/admin-password"); ok "senha do admin gravada em $STACK_ETC/admin-password"
else ok "stack.env atualizado a partir do install.conf (segredos e estado da exportação mantidos)"; fi

echo "== Credenciais OCI =="
if [ -f "${OCI_CONFIG_FILE:-/nao-existe}" ] && [ -f "${OCI_KEY_FILE:-/nao-existe}" ]; then
  install -m 600 "$OCI_KEY_FILE" "$STACK_ETC/oci/key.pem"
  sed -E "s#^key_file *=.*#key_file=/etc/oci/key.pem#" "$OCI_CONFIG_FILE" > "$STACK_ETC/oci/config"; chmod 600 "$STACK_ETC/oci/config"; ok "config e chave OCI instaladas (modo 600)"
else warn "OCI_CONFIG_FILE/OCI_KEY_FILE ausentes: exportador permanece desligado até configurar"; fi

echo "== Imagens e subida =="
if [ -d "$HERE/images" ]; then
  for t in "$HERE"/images/*.tar; do docker load -i "$t" >/dev/null; done
  while read -r ref id; do [ "$(docker image inspect -f '{{.Id}}' "$ref")" = "$id" ] || die "imagem $ref não confere com IMAGE_IDS"; done < "$HERE/images/IMAGE_IDS"
  ok "imagens carregadas e conferidas (offline)"
fi
dc(){ docker compose --env-file "$ENVF" -f "$STACK_OPT/docker-compose.yml" -p "$P" "$@"; }
[ -e "$STACK_ETC/exporter.token" ] || : > "$STACK_ETC/exporter.token"
dc up -d mongodb opensearch graylog
for i in $(seq 1 90); do [ "$(dc ps --format '{{.Health}}' graylog)" = healthy ] && break; sleep 10; done
[ "$(dc ps --format '{{.Health}}' graylog)" = healthy ] || die "graylog não ficou healthy (docker logs ${P}-graylog-1)"
. "$ENVF"; ADMPW="$(cat "$STACK_ETC/admin-password")"
GRAYLOG_ADMIN_PASSWORD="$ADMPW" python3 "$STACK_OPT/provision/provision.py" --url "http://127.0.0.1:$PORT_HTTP" --token-file "$STACK_ETC/exporter.token"
dc up -d exporter
for i in $(seq 1 30); do [ "$(dc ps --format '{{.Health}}' exporter)" = healthy ] && break; sleep 10; done
[ "$(dc ps --format '{{.Health}}' exporter)" = healthy ] || die "exporter não ficou healthy (docker logs ${P}-exporter-1)"
ok "stack no ar"

if [ "$LAB" = 0 ]; then
  install -m 755 "$STACK_OPT/scripts/graylog-stack" /usr/local/bin/graylog-stack
  install -m 644 "$HERE"/systemd/graylog-stack-watchdog.* /etc/systemd/system/
  systemctl daemon-reload; systemctl enable --now graylog-stack-watchdog.timer; ok "CLI e vigia instalados"
fi
echo "== Pronto =="; echo "UI: http://${HOST_IP}:${PORT_HTTP}   usuário: admin   senha: arquivo $STACK_ETC/admin-password"
echo "Exportação: ${EXPORT_ENABLED} (no corte: graylog-stack export on). Valide: scripts/verify.sh [--oci]"
