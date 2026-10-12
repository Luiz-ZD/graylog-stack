#!/usr/bin/env bash
# install.sh --dry-run num servidor "limpo" (sem chronyd ativo, sem docker, sem jq): precisa chegar ao fim e mostrar a transacao de pacotes.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/b/scripts" "$T/b/provision" "$T/b/docker-rpms/repodata" "$T/stubs" "$T/var"
cp "$D"/scripts/install.sh "$D"/scripts/lib-env.sh "$T/b/scripts/"; cp "$D"/docker-compose.yml "$D"/versions.env "$T/b/"; cp "$D"/install.conf.example "$T/b/install.conf"
sed -i 's/^NTP_SERVERS=.*/NTP_SERVERS="10.0.0.1 10.0.0.2"/' "$T/b/install.conf"
cat > "$T/stubs/timedatectl" <<'S'
#!/bin/sh
echo America/Sao_Paulo
S
cat > "$T/stubs/systemctl" <<'S'
#!/bin/sh
[ "$1" = is-active ] && exit 3; exit 0
S
cat > "$T/stubs/chronyc" <<'S'
#!/bin/sh
[ "$1" = waitsync ] && exit 1; echo "System time     : 0.000100 seconds fast of NTP time"
S
cat > "$T/stubs/docker" <<'S'
#!/bin/sh
exit 1
S
cat > "$T/stubs/jq" <<'S'
#!/bin/sh
exit 127
S
cat > "$T/stubs/dnf" <<'S'
#!/bin/sh
printf 'Installing:\n docker-ce  x86_64  29.9.0\nTransaction Summary\nInstall  21 Packages\n'; exit 1
S
chmod +x "$T"/stubs/*
# jq precisa parecer ausente: `command -v jq` acha o stub, entao removemos o stub e escondemos o real
rm "$T/stubs/jq"; mkdir -p "$T/bin"; for c in bash sh sed grep awk df ss cut tr head tail cat ls mkdir dirname id seq sleep sha256sum curl openssl python3 mktemp stat tee cp mv rm chmod env wc sort date uname basename; do p=$(command -v $c) && ln -sf "$p" "$T/bin/$c"; done
out=$(PATH="$T/stubs:$T/bin" STACK_VAR="$T/var/lib/gl" STACK_ETC="$T/etc" STACK_OPT="$T/opt" "$T/b/scripts/install.sh" --dry-run 2>&1); rc=$?
echo "$out" | tail -8
[ $rc = 0 ] || { echo "FALHOU: dry-run saiu com $rc"; exit 1; }
echo "$out" | grep -q 'ERRO' && { echo "FALHOU: dry-run reportou erro"; exit 1; }
echo "$out" | grep -q 'transação prevista' || { echo "FALHOU: nao mostrou a transacao de pacotes"; exit 1; }
echo "$out" | grep -q 'dry-run concluído' || { echo "FALHOU: nao concluiu"; exit 1; }
[ ! -e "$T/etc/stack.env" ] || { echo "FALHOU: dry-run alterou o sistema"; exit 1; }
echo INSTALL_DRYRUN_OK
