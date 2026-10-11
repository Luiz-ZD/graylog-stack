#!/usr/bin/env bash
# Resolve Docker CE + jq contra um userspace RHEL 9.6 (UBI 9.6) usando os repositorios 9.6 do AlmaLinux (rebuild do RHEL 9.6),
# baixando apenas o que falta nesse baseline. Gera um repositorio local em build/docker-rpms-src.
set -euo pipefail
OUT="$(cd "$(dirname "$0")/../.." && pwd)/build/docker-rpms-src"; rm -rf -- "$OUT"; mkdir -p "$OUT"
UBI="${UBI_IMAGE:-registry.access.redhat.com/ubi9/ubi:9.6}"; ALMA="${ALMA_VAULT:-https://repo.almalinux.org/vault/9.6}"
docker run --rm -v "$OUT:/out" "$UBI" bash -c '
set -e
for r in BaseOS AppStream; do
cat > /etc/yum.repos.d/alma96-$r.repo <<EOR
[alma96-$r]
name=alma96-$r
baseurl='"$ALMA"'/$r/x86_64/os/
gpgcheck=0
enabled=1
EOR
done
cat > /etc/yum.repos.d/docker-ce.repo <<EOR
[docker-ce-stable]
name=docker-ce-stable
baseurl=https://download.docker.com/linux/rhel/9/x86_64/stable
gpgcheck=1
gpgkey=https://download.docker.com/linux/rhel/gpg
enabled=1
EOR
dnf -y -q --disablerepo="*" --enablerepo="alma96-*" --enablerepo=docker-ce-stable --setopt=install_weak_deps=False \
  install --downloadonly --downloaddir /out docker-ce docker-ce-cli containerd.io docker-compose-plugin jq 2>&1 | tail -3
ls /out | wc -l'
docker run --rm -v "$OUT:/out" almalinux:9 bash -c 'dnf -y -q install createrepo_c >/dev/null 2>&1 && createrepo_c -q /out && ls /out'
