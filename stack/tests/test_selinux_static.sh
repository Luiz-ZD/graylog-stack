#!/usr/bin/env bash
# Regressao do achado em RHEL com SELinux Enforcing: o systemd (init_t) nao executa script com rotulo admin_home_t.
# 1) a unit chama o script via /bin/bash; 2) o install.sh restaura o contexto de /opt/graylog-stack.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"
grep -q '^ExecStart=/bin/bash /opt/graylog-stack/scripts/watchdog.sh' "$D/systemd/graylog-stack-watchdog.service" || { echo "FALHOU: unit deve usar ExecStart=/bin/bash ..."; exit 1; }
grep -q 'restorecon -R "\$STACK_OPT"' "$D/scripts/install.sh" || { echo "FALHOU: install.sh deve rodar restorecon em STACK_OPT"; exit 1; }
echo SELINUX_STATIC_OK
