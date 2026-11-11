# Подключение с устройств

Настройки сервера (одинаковые для любого клиента):

| Параметр | Значение |
|---|---|
| Адрес сервера | `82.148.226.31` |
| Порт | `443` |
| Протокол | `VLESS` |
| Flow | `xtls-rprx-vision` |
| Transport | `tcp` |
| Security | `REALITY` |
| SNI (serverName) | `notion.so` |
| Public key (pbk) | `3IRcbkI6-igCBuJFL9CfaWxBHdEaO1mNBFNeCcXudho` |
| Short ID (sid) | `a0e67b6f` |
| Fingerprint (fp) | `chrome` |
| SpiderX (spx) | `/` |
| UUID | `06eeb7ee-aeb7-40f5-86da-4b898e212fcb` |

Проще всего — импортировать ссылку (файл [../client/vless-url.txt](../client/vless-url.txt)):

```
vless://06eeb7ee-aeb7-40f5-86da-4b898e212fcb@82.148.226.31:443?encryption=none&flow=xtls-rprx-vision&fp=chrome&pbk=3IRcbkI6-igCBuJFL9CfaWxBHdEaO1mNBFNeCcXudho&security=reality&sid=a0e67b6f&sni=notion.so&spx=%2F8f9a0ab5def0224&support-x25519mlkem768=true&type=tcp#VLESS-Reality-443-main
```

Подписка (клиент сам подтянет/обновит конфиг):
`http://82.148.226.31:2096/4zbxad4mwilt8wjw/mainsub01`

### ⚠️ После каждой ротации: обновляйте ПРОФИЛЬ, а не только ссылку

Самая частая причина «всё сломалось после ротации»: в клиенте остаётся **старый профиль**
со старыми ключами. Приложение пишет «подключено», но трафик не идёт.

Два способа:

| Способ | Что делать после `./rotate.sh` |
|---|---|
| **Подписка** (рекомендую) | в клиенте «Обновить подписку» — профиль подтянется сам |
| **Ссылка/QR** | удалить старый профиль и импортировать новый `client/vless-url.txt` / `qr/main-<порт>.png` |

Подписка: `http://82.148.226.31:2096/4zbxad4mwilt8wjw/mainsub01`

В Streisand: `Settings → Subscriptions → +` → вставить URL → `Update`.
Профиль обновится вместе с ключами и портом.

### Для телефона — отдельная подписка (два профиля сразу)


```
http://82.148.226.31:2096/4zbxad4mwilt8wjw/phonesub01
```

В ней лежат два профиля: основной :443 (SNI `cdn.jsdelivr.net`) и резервный :8443
(SNI `www.python.org`). Если основной перестанет работать — переключитесь на резервный
в списке серверов, ничего вводить не нужно.

| Параметр | :443 (основной) | :8443 (резерв) |
|---|---|---|
| Порт | 443 | 8443 |
| SNI | `cdn.jsdelivr.net` | `www.python.org` |
| Public key | `OU0AvToZSJPrfppeSQ7R3k_Bo3dwO-UBzmkmNL72FTM` | `GhlACaIyiC5RmlMaHQn77shBcpeeFZxqbNk-T_efDgc` |
| Short ID | `17ccf52039c254df` | `ced31a3dfc59cb94` |
| UUID (телефон) | `3def1d1b-8431-4f46-a65d-40c1b6b4e4d4` | `3def1d1b-8431-4f46-a65d-40c1b6b4e4d4` |

QR-коды: [../qr/phone-443.png](../qr/phone-443.png) и [../qr/phone-8443.png](../qr/phone-8443.png).
Ссылки: [../client/vless-phone-443.txt](../client/vless-phone-443.txt),
[../client/vless-phone-8443.txt](../client/vless-phone-8443.txt).

> UUID `phone` отличается от UUID ПК (`main`) намеренно: телефон можно отозвать
> отдельно и видеть его трафик отдельной строкой в панели.

---

## Windows

1. **v2rayN** (популярный, простой): https://github.com/2dust/v2rayN/releases
   - Распаковать, запустить `v2rayN.exe`.
   - `Сервер` → `Импорт из буфера обмена` (ссылка `vless://` уже в буфере).
   - Внизу справа выбрать сервер, режим «Режим правил» (Rule) или «Глобальный» (Global).
   - Включить: `Системный прокси` → `Автоматически`.
2. **Nekoray / Throne** (UI понятнее): https://github.com/throneproj/Throne/releases
   - `Программа` → `Добавить профиль из буфера обмена` → Enter. Затем `TUN` или `Системный прокси`.

## macOS

Самый простой и проверенный путь — **локальный запуск из проекта** (без сторонних приложений):

```bash
./mac-vpn.sh --test     # проверить конфиг
./mac-vpn.sh            # поднять туннель (SOCKS 1080 + HTTP 1081)
./mac-vpn.sh --system   # + системный прокси macOS (DNS через TUN не идёт, см. ниже)
```

- **Hiddify** (App Store / GitHub) — импорт ссылки или подписки, включить «VPN-профиль»
  (TUN-режим, DNS через туннель — самый надёжный вариант для браузера).
- **Nekoray / Throne** — как на Windows, включать режим TUN.
- **sing-box (CLI, если нужен только прокси)**:
  ```bash
  brew install sing-box
  # положить конфиг из client/config.json (там уже все параметры), затем:
  sing-box run -c client/config.json     # SOCKS5 127.0.0.1:1080, HTTP 127.0.0.1:1081
  curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org   # должен вернуть 82.148.226.31
  ```

## Android

- **v2rayNG**: https://github.com/2dust/v2rayNG/releases
  `+` (справа сверху) → `Импорт конфигурации из буфера обмена` → выбрать профиль → «Подключиться».
- **Hiddify** — то же самое, плюс умеет подписку и TUN-режим без root.

## iOS

- **Streisand** (бесплатно), **Shadowrocket** (платно), **Hiddify**.
  Импорт по ссылке или «Добавить подписку» с URL подписки.

## Linux (десктоп/сервер)

- **Nekoray** (GUI), **Hiddify**, либо Xray/sing-box из `client/config.json`.
- Быстрая проверка без установки — как в `./test-tunnel.sh`: контейнер + Xray.

---

## «Подключается, но работает только google.com» (или часть сайтов)

Это **не проблема сервера** — туннель установлен, но трафик/ DNS обрабатывается клиентом
неправильно. Проверено: с этого же Mac через `./mac-vpn.sh` открываются все сайты,
а с сервера 5/5 по google/youtube/github/discord/apple/wikipedia.

Причины по частоте:

1. **DNS не идёт через VPN** (самое частое). Провайдер отдаёт свою «заглушку» или
   отказывает в резолве — в итоге открывается только то, что уже в кэше/IP-адресе.
   - v2rayN: `Настройки → Настройки DNS` → включить `Use system hosts` off и
     `Remote DNS` = `https://1.1.1.1/dns-query`; либо включить `TUN-режим`.
   - v2rayNG (Android): в профиле включить «DNS через прокси» / `Remote DNS`.
   - Hiddify: включить **TUN** (режим VPN), DNS по умолчанию идёт через туннель.
2. **Режим «по правилам» с пустой/битой geo-базой.** v2rayN/v2rayNG в режиме `Rule`
   пускают напрямую всё, что не попало в список. Переключите на **Global / Глобальный**
   на 5 минут для проверки.
3. **Mux / Fragment включены криво.** Отключите `Mux` (мультиплексирование) — с Vision
   он не нужен и часто рвёт соединения.
4. **Системный прокси включён, а DNS — нет.** В macOS/Windows системный «SOCKS-прокси»
   не проксирует DNS. Нужен TUN-режим (Hiddify, Nekoray/Throne) или `./mac-vpn.sh --system`
   + проверка в браузере.
5. **Старый профиль от предыдущей ротации ключей.** После `rotate.sh` старые ссылки
   невалидны — молча не работает. Удалите профиль и импортируйте заново из `client/vless-*.txt`.

### Как проверить, что дело в клиенте, а не в сервере

```bash
./mac-vpn.sh --test      # конфиг валиден?
./mac-vpn.sh             # поднимет туннель локально и проверит IP
curl --socks5-hostname 127.0.0.1:1080 https://www.youtube.com -o /dev/null -w "%{http_code}\n"
```

Если `mac-vpn.sh` показывает IP `82.148.226.31` и сайты открываются — сервер исправен,
настраивайте клиент (пункты 1–3 выше) либо пользуйтесь `./mac-vpn.sh --system`.

### Резервный вход

Если на :443 нестабильно, а на :8443 работает — импортируйте профиль :8443
(`client/vless-phone-8443.txt`, SNI `www.python.org`). Он на другом порту и с другими ключами.

## Если клиент не подключается

1. Проверить, что провайдер/сеть не блокирует IP: `nc -z -G 5 82.148.226.31 443`.
2. Проверить, что сервер отдаёт «правильный» сертификат `cdn.jsdelivr.net`:
   ```bash
   echo | openssl s_client -connect 82.148.226.31:443 -servername cdn.jsdelivr.net -tls1_3 -alpn h2 2>/dev/null \
     | grep -E "subject=|ALPN"
   # ожидаемо: subject=...CN=*.jsdelivr.net и ALPN protocol: h2
   ```
3. Сверить `pbk`, `sid`, `sni`, `fp` с таблицей выше — 90% проблем это опечатка в одном символе.
4. Посмотреть логи клиента (в v2rayN: `Настройки → Журнал`), на сервере — `./rssh.sh 'x-ui log'`.
5. Если у клиента старый Xray (< 1.8), обновить приложение: Reality поддерживается не везде.
