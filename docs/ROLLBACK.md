# Откат конфигурации (снапшоты)

Любое изменение туннеля сохраняется в `docs/snapshots/<дата>/`. Здесь лежат полные
конфиги: инбаунды (с приватными ключами), клиентские конфиги, `vpn.json`, QR.

> ⚠️ В снапшотах есть **приватные ключи Reality**. Папка `docs/` не в `.gitignore`
> (git в проекте не инициализирован). Не публикуйте её. Если будете делать репозиторий —
> добавьте `docs/snapshots/` в `.gitignore`.

## Что есть

| Снапшот | Что внутри |
|---|---|
| `2026-11-05-pre-rotation/` | состояние **до** смены SNI и ротации ключей: 443 → `www.apple.com`, 8443 → `www.python.org`, старые ключи |
| `2026-11-05-post-rotation/` | текущее рабочее: 443 → `cdn.jsdelivr.net`, 8443 → `www.python.org`, новые ключи |
| `2026-11-05_<время>-rotate/` | авто-снапшоты `rotate.sh`: время ротации в названии, внутри — `inbound-1.json`, `inbound-2.json`, клиентский конфиг, ссылка, ключи, QR |

Структура каждого:

```
inbounds.json          # всё состояние инбаундов (список)
inbound-1.json         # готовый payload для API: инбаунд 443
inbound-2.json         # готовый payload для API: инбаунд 8443
client-config.json     # клиентский конфиг Xray на момент снапшота
vless-url.txt          # ссылка для импорта на момент снапшота
vpn-keys.json          # ключи/SNI/shortId (для справки)
qr/                    # QR-коды на момент снапшота
```

## Откат инбаундов на сервере

Вернуть **один** инбаунд:

```bash
# 443 — вернуть apple-конфиг со старыми ключами
./xui-api.sh POST /panel/api/inbounds/update/1 docs/snapshots/2026-11-05-pre-rotation/inbound-1.json

# 8443 — вернуть старые ключи
./xui-api.sh POST /panel/api/inbounds/update/2 docs/snapshots/2026-11-05-pre-rotation/inbound-2.json
```

Вернуть **всё** состояние разом (оба инбаунда):

```bash
cd docs/snapshots/2026-11-05-pre-rotation
for f in inbound-*.json; do
  id=$(basename "$f" .json | sed 's/inbound-//')
  ../../xui-api.sh POST /panel/api/inbounds/update/$id "$f"
done
cd -
```

После отката нужно вернуть и клиентские файлы, иначе в них будут новые ключи:

```bash
SNAP=docs/snapshots/2026-11-05-pre-rotation
cp "$SNAP/client-config.json" client/config.json
cp "$SNAP/vless-url.txt"      client/vless-url.txt
cp "$SNAP/vpn-keys.json"      secrets/vpn.json
cp "$SNAP/qr/"*.png           qr/
```

Либо проще — откатить инбаунды, а локальные файлы пересобрать из панели:

```bash
./sync-client.sh      # возьмёт актуальные ссылки из панели и перезапишет config/QR
```

Проверка после отката:

```bash
./diag.sh
```

## Откат БД панели целиком

Полный бэкап (клиенты, инбаунды, настройки) лежит в `backups/x-ui-*.db`.

```bash
ls backups/                                  # выбрать нужный
./rssh.sh -f backups/x-ui-2026-11-04_1431.db 'cat > /etc/x-ui/x-ui.db'
./rssh.sh 'systemctl restart x-ui'
./sync-client.sh                             # подтянуть ссылки после отката
```

Внимание: откат БД вернёт и клиентов (UUID), поэтому профили на устройствах снова
станут валидными в том виде, в котором были на момент бэкапа.

## Откат к предыдущему снапшоту в одну команду

```bash
./rollback.sh 2026-11-05-pre-rotation
```

Скрипт делает всё: инбаунды + клиентские файлы + QR + проверка.
