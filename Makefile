# VPN: VLESS + Reality на 3x-ui
#
# Первая установка (спросит IP, логин, пароль и попросит подтверждение):
#     make install
#
# Без вопросов (для автоматизации):
#     make install S_HOST=1.2.3.4 S_USER=root S_PASS=... CONFIRM=yes
#
# Полный список: make help
SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- параметры (можно переопределить: make install S_HOST=...) ---
S_HOST ?=
S_USER ?= root
S_PASS ?=
S_SSH_PORT ?= 22
S_MAIN_PORT ?= 443
S_BACKUP_PORT ?= 8443
S_SNI ?= www.apple.com
S_SNI2 ?= www.python.org
PROV_ON_EXISTS ?= abort
CONFIRM ?=

export S_HOST S_USER S_PASS S_SSH_PORT S_MAIN_PORT S_BACKUP_PORT S_SNI S_SNI2
export PROV_ON_EXISTS CONFIRM

.PHONY: help install doctor diag test rotate rotate-port backup rollback panel \
        links status clean-prov

help: ## показать эту справку
	@echo ""
	@echo "  VPN: VLESS + Reality на 3x-ui"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "  %-18s %s\n", "команда", "что делает"; print "  " sprintf("%.0s", "────────────────────────────────────────────────────")} \
	     /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "  Параметры установки (переопределяются через =):"
	@echo "    S_HOST=<ip>          адрес сервера"
	@echo "    S_USER=root          пользователь SSH"
	@echo "    S_PASS=<пароль>      пароль SSH"
	@echo "    S_MAIN_PORT=443      порт основного входа"
	@echo "    S_BACKUP_PORT=8443   порт резервного входа"
	@echo "    S_SNI / S_SNI2       домены-маскировки"
	@echo "    CONFIRM=yes          без интерактивного подтверждения"
	@echo "    PROV_ON_EXISTS=abort|force   что делать, если 3x-ui уже стоит"
	@echo ""

install: ## установить VPN на чистый сервер (интерактивно)
	@bash provision/install.sh

doctor: ## проверить готовность машины и сервера
	@echo "== локальные зависимости =="
	@for t in python3 ssh sshpass curl docker git; do \
	  if command -v $$t >/dev/null 2>&1; then echo "  ✓ $$t"; else echo "  ✗ $$t  (установите: brew install $$t)"; fi; \
	done
	@echo "== конфигурация проекта =="
	@test -f secrets/server.json && echo "  ✓ secrets/server.json" || echo "  — secrets/server.json (нет: нужен make install)"
	@test -f secrets/vpn.json    && echo "  ✓ secrets/vpn.json"    || echo "  — secrets/vpn.json (нет: нужен make install)"
	@echo "== доступность сервера =="
	@H=$$(python3 -c "import json;print(json.load(open('secrets/server.json'))['host'])" 2>/dev/null); \
	 if [ -n "$$H" ]; then \
	   for p in 22 443 8443; do \
	     if nc -z -G 5 $$H $$p 2>/dev/null; then echo "  ✓ $$H:$$p"; else echo "  ✗ $$H:$$p"; fi; \
	   done; \
	 else echo "  — не задан сервер"; fi

diag: ## послойная диагностика туннеля
	@./diag.sh

test: ## проверить туннель в контейнере
	@./test-both.sh

status: ## состояние входов и клиентов на сервере
	@./rssh.sh 'echo "== x-ui =="; systemctl is-active x-ui; \
	  echo "== порты =="; ss -tulpn | grep -E ":443 |:8443 " || true; \
	  echo "== клиенты =="; sqlite3 -separator " | " /etc/x-ui/x-ui.db \
	    "select email, round(down/1048576.0,1)||\"MB\", datetime(last_online/1000,\"unixepoch\") from client_traffics"'

rotate: ## ротация ключей и SNI (см. docs/ROTATION.md)
	@./rotate.sh

rotate-port: ## ротация со сменой порта
	@./rotate.sh --change-port

backup: ## бэкап базы панели в backups/
	@./backup.sh

rollback: ## откат к снапшоту (make rollback S=2026-11-05_120000-rotate)
	@./rollback.sh $(S)

panel: ## открыть туннель к панели 3x-ui
	@./panel-tunnel.sh

links: ## показать ссылки для подключения
	@echo "== основная =="; cat client/vless-url.txt 2>/dev/null || echo "нет"
	@echo; echo "== резервная =="; cat client/vless-backup.txt 2>/dev/null || echo "нет"
	@echo; echo "== подписка =="; python3 -c "import json;print(json.load(open('secrets/vpn.json'))['subscription_url'])" 2>/dev/null || echo "нет"

clean-prov: ## удалить временные файлы провижининга
	@rm -f /tmp/prov-keys.env /tmp/prov-ids.env /tmp/prov-token.txt \
	       /tmp/prov-main.json /tmp/prov-backup.json /tmp/prov-list.json /tmp/prov-payload.json
	@echo "временные файлы удалены"
