#!/usr/bin/env bash
# Instala Docker CE + jq OFFLINE (repositorio local) no userspace do RHEL 9.6 (UBI 9.6); nao pode atualizar pacotes do sistema.
set -uo pipefail
R="$(cd "$(dirname "$0")/../../.." && pwd)/build/docker-rpms-src"; [ -d "$R/repodata" ] || { echo "FALHOU: rode scripts/build-rpms.sh"; exit 1; }
out=$(docker run --rm -v "$R:/rpms:ro" "${UBI_IMAGE:-registry.access.redhat.com/ubi9/ubi:9.6}" bash -c '
 dnf -y --disablerepo="*" --repofrompath=gb,/rpms --setopt=gb.gpgcheck=0 --setopt=install_weak_deps=False install docker-ce docker-ce-cli containerd.io docker-compose-plugin jq 2>&1
 echo "---"; rpm -q docker-ce docker-compose-plugin jq container-selinux' 2>&1)
echo "$out" | tail -6
echo "$out" | grep -q 'Complete!' || { echo "FALHOU: transacao nao concluiu"; exit 1; }
echo "$out" | grep -qE '^\s*Upgrad' && { echo "FALHOU: atualizaria pacotes do sistema"; exit 1; }
echo RPM_CLOSURE_OK
