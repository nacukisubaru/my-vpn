#!/bin/bash
# Шаг 1: базовая подготовка сервера.
# пакеты, BBR, firewall (порт SSH открывается ДО включения ufw).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

step "1/6 базовая подготовка"

info "определяю ОС"
OS=$(srv 'cat /etc/os-release | grep -E "^(ID|VERSION_ID)=" | tr "\n" " "') \
  || die "нет SSH-доступа к $S_USER@$S_HOST"
ok "$OS"

info "обновляю списки пакетов"
srv 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq' >/dev/null 2>&1 \
  || die "apt-get update не удался"
ok "apt-get update"

info "устанавливаю пакеты: curl socat cron ufw sqlite3 ca-certificates"
srv 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y -qq curl socat cron ufw sqlite3 ca-certificates openssl' \
  >/dev/null 2>&1 || die "не удалось установить пакеты"
ok "пакеты установлены"

info "включаю BBR (ускорение TCP)"
srv 'modprobe tcp_bbr 2>/dev/null || true
     printf "net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n" > /etc/sysctl.d/99-vpn.conf
     sysctl --system >/dev/null 2>&1 || true' >/dev/null 2>&1
CC=$(srv 'sysctl -n net.ipv4.tcp_congestion_control' | tr -d '\r')
[ "$CC" = "bbr" ] && ok "congestion control: bbr" || warn "bbr не применился (осталось $CC) — не критично"

info "настраиваю firewall (ufw)"
# ВАЖНО: SSH открываем ПЕРВЫМ, иначе ufw обрежет доступ к серверу
SSH_PORT=${S_SSH_PORT:-22}
srv "ufw --force reset >/dev/null 2>&1 || true
     ufw default deny incoming >/dev/null
     ufw default allow outgoing >/dev/null
     ufw allow ${SSH_PORT}/tcp >/dev/null
     ufw --force enable >/dev/null 2>&1 || true" >/dev/null 2>&1 \
  || die "не удалось настроить ufw"
ok "ufw включён, SSH (${SSH_PORT}/tcp) разрешён"

# контрольная проверка, что SSH ещё жив после ufw
srv 'true' || die "SSH перестал отвечать после включения ufw — проверьте консоль хостера"
ok "SSH доступен после включения ufw"

info "очищаю временные файлы"
srv 'rm -f /root/install-3x-ui.sh' >/dev/null 2>&1 || true
ok "готово"
