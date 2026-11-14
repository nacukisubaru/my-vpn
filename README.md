# Свой VPN на сервере 82.148.226.31

VLESS + Reality + XTLS-Vision на 3x-ui (Xray-core). Трафик неотличим от обычного HTTPS
к крупному сайту — нет ни пароля, ни заголовков, которые можно распознать DPI.

## 1. Что настроено

| Компонент | Значение |
|---|---|
| Сервер | `82.148.226.31` (Debian 13, 1 vCPU, 3.9 GB RAM, гео-база: UK) |
| Панель | 3x-ui **v3.11.0**, `http://127.0.0.1:38217/lVsDniTvh17lDbpiAV/` |
| Ядро | Xray-core **26.10.21** |
| Inbound основной | `VLESS-Reality-443` (id 1): VLESS + `xtls-rprx-vision`, TCP :443, REALITY |
| Inbound резервный | `VLESS-Reality-8443-backup` (id 2): тот же протокол, TCP :8443 |
| dest / SNI (443) | `notion.so:443` / `notion.so` |
| dest / SNI (8443) | `www.python.org:443` / `www.python.org` |
| uTLS-fingerprint | `chrome` |
| shortId (443 / 8443) | `a0e67b6f` / `ced31a3dfc59cb94` |
| Клиенты | `main` (ПК), `phone` (телефон, в обоих инбаундах), `backup` (только 8443) |
| Сеть | BBR + fq, ufw: разрешены 22/tcp, 443/tcp, 8443/tcp, 2096/tcp |
| Автозапуск | `x-ui.service` — enabled (переживает ребут) |

Почему так: Reality не требует своего домена и сертификата — сервер на :443 реально
проксирует TLS-хендшейк на `cdn.jsdelivr.net` и отдаёт его настоящий сертификат.
Активный обход/замер трафика видит обычный HTTPS к этому сайту. Vision нужен, чтобы
убрать характерные TLS-in-TLS «отпечатки» и снизить overhead.

> **История:** изначально SNI был `www.microsoft.com` (нестабильный IPv6 с сервера), затем
> `www.apple.com`, а с 2026-11-05 — `cdn.jsdelivr.net` с полностью новыми ключами Reality
> (см. [docs/ROLLBACK.md](docs/ROLLBACK.md), там же откат).

## 1.5. Установка с нуля

```bash
make install      # спросит IP, логин, пароль SSH и попросит подтверждение
```

Ставит 3x-ui, генерирует ключи, создаёт оба инбаунда, пишет `secrets/`, `client/`, `qr/`
и проверяет туннель. Если 3x-ui уже установлен — **останавливается**, ничего не меняя
(`PROV_ON_EXISTS=force` для переустановки). Подробно: [docs/ADMIN.md](docs/ADMIN.md#установка-с-нуля-провижининг).

```bash
make help        # все команды
make doctor      # проверка перед установкой
```

## 2. Как подключиться

Ссылка (импортируется в любое приложение, см. [docs/CLIENTS.md](docs/CLIENTS.md)):

```
vless://06eeb7ee-aeb7-40f5-86da-4b898e212fcb@82.148.226.31:443?encryption=none&flow=xtls-rprx-vision&fp=chrome&pbk=3IRcbkI6-igCBuJFL9CfaWxBHdEaO1mNBFNeCcXudho&security=reality&sid=a0e67b6f&sni=notion.so&spx=%2F8f9a0ab5def0224&support-x25519mlkem768=true&type=tcp#VLESS-Reality-443-main
```

Она же лежит в [client/vless-url.txt](client/vless-url.txt).

Подписка (авто-обновление конфига на телефоне, 3x-ui сам отдаёт ссылки):

```
http://82.148.226.31:2096/4zbxad4mwilt8wjw/mainsub01
```

Адрес подписки меняется в панели (Настройки → Подписка), путь рандомизирован намеренно.

### Для телефона (отдельный клиент `phone`)

Телефон заведён отдельным UUID (можно отозвать, не трогая ПК) и работает с **обоих** входов.
В приложении достаточно добавить **подписку** — она отдаст оба конфига сразу:

```
http://82.148.226.31:2096/4zbxad4mwilt8wjw/phonesub01
```

Или импортировать по одной ссылке / QR:

- основной, :443 (SNI `cdn.jsdelivr.net`) — [client/vless-phone-443.txt](client/vless-phone-443.txt), QR: [qr/phone-443.png](qr/phone-443.png)
- резервный, :8443 (SNI `www.python.org`) — [client/vless-phone-8443.txt](client/vless-phone-8443.txt), QR: [qr/phone-8443.png](qr/phone-8443.png)

```
vless://3def1d1b-8431-4f46-a65d-40c1b6b4e4d4@82.148.226.31:443?encryption=none&flow=xtls-rprx-vision&fp=chrome&pbk=OU0AvToZSJPrfppeSQ7R3k_Bo3dwO-UBzmkmNL72FTM&security=reality&sid=17ccf52039c254df&sni=cdn.jsdelivr.net&spx=%2F0adf54d86bb61d5&support-x25519mlkem768=true&type=tcp#VLESS-Reality-443-phone
```

```
vless://3def1d1b-8431-4f46-a65d-40c1b6b4e4d4@82.148.226.31:8443?encryption=none&flow=xtls-rprx-vision&fp=chrome&pbk=GhlACaIyiC5RmlMaHQn77shBcpeeFZxqbNk-T_efDgc&security=reality&sid=32f98b32&sni=www.python.org&spx=%2F0adf54d86bb61d5&support-x25519mlkem768=true&type=tcp#VLESS-Reality-8443-backup-phone
```

### Резервный вход :8443 — зачем

Если 443 начнут резать/троттлить (или заблокируют домен-маскировку), переключаетесь
на второй профиль в клиенте — он ходит на 8443 под маской `www.python.org`, с другими ключами
Reality (`pbk`/`sid`). Настраивать заново ничего не нужно: профиль уже в подписке и в QR.

## 3. Панель управления (админка)

| | |
|---|---|
| **URL** | `http://localhost:38217/lVsDniTvh17lDbpiAV/` (после `./panel-tunnel.sh`) |
| **Логин** | `admJgOJhmxfw` |
| **Пароль** | `WubkxKMe6GrZAV4CZWs3wGFK` |
| **API-токен** | `fQUwOl0eKn2eIm6Ytn8wJjgvZ4IbcL5hsr35ToGAD5WWVUac` |

Как открыть (панель слушает только `127.0.0.1` на сервере — снаружи недоступна,
чтобы её не сканили и не брутфорсили):

```bash
./panel-tunnel.sh          # поднимет SSH-туннель и покажет URL + логин/пароль
# затем в браузере: http://localhost:38217/lVsDniTvh17lDbpiAV/
```

Копия доступов: [secrets/CREDENTIALS.md](secrets/CREDENTIALS.md), [secrets/panel.json](secrets/panel.json)
(права 600, папка в `.gitignore`).

> Если хотите открыть панель наружу (без туннеля, прямо с телефона) — см.
> [docs/ADMIN.md](docs/ADMIN.md#открыть-панель-наружу-опционально) с плюсами/минусами.

## 3.5. Если VPN перестал работать

Порядок действий (2 минуты):

```bash
./diag.sh
```

Скрипт проверяет по слоям и печатает вердикт:

| Что показал `diag.sh` | Что это значит | Что делать |
|---|---|---|
| П.1 «порт недоступен» | блок по IP/порту у провайдера | `./rotate.sh --port 443` (сменит порт) или сменить IP |
| П.2 «ПРОВАЛ» (нет TLS) | блок по SNI/домену-маскировке | `./rotate.sh --sni <другой домен>` |
| П.2 ок, П.3 «не работает» | проблема в ключах/клиенте | `./sync-client.sh` и переимпортировать профиль |
| Всё ок | сервер в порядке, дело в клиенте | `./mac-vpn.sh` (проверка с Mac) и [docs/CLIENTS.md](docs/CLIENTS.md#подключается-но-работает-только-googlecom-или-часть-сайтов) |

Сброс «отпечатка» одной командой (случайный SNI из проверенного пула + новые ключи):

```bash
./rotate.sh                  # случайный SNI + новые ключи
./rotate.sh --list-sni       # посмотреть пул и статусы
```

Все флаги (`--without-sni`, `--change-port`, `--sni`, `--port`, `--no-keys`, `--verify-sni`,
`--reset-used`) — в [docs/ROTATION.md](docs/ROTATION.md).

После ротации ключи меняются — **старые профили на устройствах перестанут работать**,
нужно заново импортировать ссылку или подписку (QR в `qr/`). Откат — `./rollback.sh <снапшот>`,
подробности в [docs/ROLLBACK.md](docs/ROLLBACK.md).

Если изменили только ключи на сервере, а устройство осталось со старым профилем — оно
будет «подключаться» и молча не работать. Это самая частая причина «VPN сломался».

## 3.6. Почему «в контейнере работает, а у меня блок»

Подробно — [docs/CLIENT-SETUP.md](docs/CLIENT-SETUP.md). Коротко: контейнер гонит один `curl`
по TCP с парой доменов. Телефон гонит **все приложения сразу, включая QUIC/UDP**, и за неделю
набрал 18 ГБ. Разница в профиле трафика — и есть причина.

Что делать (по важности):

1. **Блокировать QUIC** для проксируемых доменов — готово в
   [`client/config-hardened.json`](client/config-hardened.json). UDP внутри VLESS/TCP
   не защищён Vision и является главным признаком для DPI.
2. **DNS через туннель** (DoH) — тоже там, утечки нет.
3. **Сплит-туннель**: через VPN только нужное ([`data/rules-proxy.txt`](data/rules-proxy.txt)),
   российское — напрямую ([`data/rules-direct.txt`](data/rules-direct.txt)).
4. **Mux выключить**, режим клиента — TUN.
5. Клиент: удобнее **Hiddify** (per-app + routing), но и **v2raytun** подходит, если
   импортировать `config-hardened.json` вместо простой ссылки.

```bash
# конфиг пересобирается автоматически при каждой ротации
./sync-client.sh
# скопировать client/config-hardened.json → импорт в клиенте
```

## 4. Проверка работы туннеля

```bash
./test-tunnel.sh
```

Скрипт собирает docker-образ с клиентом Xray-core, поднимает изолированный контейнер
и гоняет проверки **внутри** контейнера (сеть хоста и ваше соединение не затрагиваются).

Последний прогон:

| Проверка | Результат |
|---|---|
| IP без туннеля (провайдер) | `89.125.128.15` |
| IP через туннель | `82.148.226.31` ✅ |
| google.com / youtube.com / apple.com | 200 / 200 / 200 ✅ |
| gstatic.com/generate_204 | 204 ✅ |
| Стабильность: 10 запросов подряд | 10/10 ✅ |
| Скорость (10 MB, Cloudflare) | 1.7–3.3 MB/s (≈14–26 Mbit/s) |
| HTTP-прокси 1081 для браузера | работает |
| Маскировка снаружи | настоящий сертификат `cdn.jsdelivr.net`, ALPN h2 ✅ |

Скорость ограничена одним ядром сервера и шифрованием Vision; для серфинга/YouTube
её достаточно. Если нужен запас — см. раздел «Что можно улучшить» в [docs/ADMIN.md](docs/ADMIN.md).

## 5. Файлы в проекте

| Файл | Назначение |
|---|---|
| `Makefile` | `make install` — установка с нуля; `make help` — все команды |
| `provision/` | шаги провижининга (база → 3x-ui → ключи → инбаунды → файлы → проверка) |
| `rssh.sh` | запуск команд на сервере по SSH (с ретраями); пароль в `secrets/server.json` |
| `panel-tunnel.sh` | SSH-туннель к панели 3x-ui |
| `xui-api.sh` | вызовы API панели (`GET/POST /panel/api/...`) без браузера |
| `test-tunnel.sh` | проверка туннеля в docker-контейнере |
| `test-both.sh` | проверка обоих входов (443 и 8443) в контейнерах |
| `diag.sh` | послойная диагностика (сеть → TLS → туннель) с вердиктом |
| `vpn-tun.sh` | **полный VPN на macOS (TUN, sing-box)** — покрывает браузер и все приложения, `sudo` |
| `vpn-browser.sh` | системный прокси macOS без sudo (HTTP 1081 + SOCKS 1080) + автовосстановление |
| `connect-link.sh` | подключение по ссылке нативно (SOCKS 11080), с проверкой байтов и логом |
| `vpn-doctor.sh` | диагностика «каши» из VPN-клиентов и залипших прокси на Mac |
| `phone-check.sh` | реально ли телефон гонит трафик (по базе панели) |
| `rotate.sh` | ротация: случайный SNI/порт + новые ключи, список/проверка пула ([docs/ROTATION.md](docs/ROTATION.md)) |
| `verify-sni.sh` | реальная проверка домена как SNI (туннель в контейнере) |
| `sync-client.sh` | подтягивает ссылки/конфиги/QR из панели (источник истины) |
| `rollback.sh` | откат к снапшоту из `docs/snapshots/` |
| `change-dest.sh` | смена домена-маскировки (dest/SNI) с проверкой домена |
| `backup.sh` | бэкап БД панели в `backups/` |
| `client/config.json` | простой конфиг (SOCKS 1080 + HTTP 1081) — для тестов |
| `client/config-hardened.json` | **конфиг с маршрутизацией**: блок QUIC, DNS в туннель, сплит-туннель |
| `client/config-phone443.json`, `client/config-phone8443.json` | те же конфиги для клиента `phone` |
| `client/Dockerfile` | образ клиента (Alpine + Xray-core) |
| `client/vless-url.txt`, `client/vless-phone-443.txt`, `client/vless-phone-8443.txt`, `client/vless-backup-8443.txt` | ссылки `vless://` для импорта |
| `qr/phone-443.png`, `qr/phone-8443.png` | QR-коды для телефона |
| `artifacts/inbound-443.json`, `artifacts/inbound-8443.json` | JSON инбаундов |
| `secrets/` | пароли/ключи (не в git, chmod 600) |
| `docs/MAC-CONNECT.md` | **подключение на macOS: TUN / системный прокси / SOCKS**, разбор проблем |
| `docs/CLIENT-SETUP.md` | как настроить клиент, чтобы не ловить блок (QUIC, DNS, сплит-туннель) |
| `docs/CLIENTS.md` | подключение с Windows/macOS/Android/iOS |
| `docs/ADMIN.md` | добавить клиента, сменить SNI, обновить, бэкап, диагностика |
| `docs/ROLLBACK.md` | снапшоты конфигов и откат на предыдущее состояние |
| `docs/ROTATION.md` | все команды ротации: SNI, порты, ключи, карантин |
| `data/sni.txt`, `data/ports.txt` | пулы доменов и портов (правятся руками) |
| `data/rules-proxy.txt` | домены, которые идут через VPN |
| `data/rules-direct.txt` | домены, которые идут напрямую |
| `docs/CLIENTS.md` | в т.ч. разбор «работает только google.com» |
| `docs/snapshots/` | сохранённые конфиги (до/после ротации 2026-11-05) |

## 6. Что можно поменять в архитектуре (на будущее)

- **Сменить SNI/dest**, если начнут фильтровать домен-маскировку: `./rotate.sh --sni <домен>` —
  проверяет домен с сервера и переключает туннель одной командой. Таблица проверенных
  кандидатов — в [docs/ADMIN.md](docs/ADMIN.md).
- **Третий вход** (например XHTTP на :8080 за Caddy) — если начнут резать и 443, и 8443.
- **XHTTP / Hysteria2 / AmneziaWG** — если понадобится UDP-транспорт или обход жёсткого
  троттлинга; сейчас для российских реалий Reality+Vision — самый устойчивый вариант.
- **x25519mlkem768 (post-quantum)** — 3x-ui v3 умеет, включается в настройках Reality.

## 7. Безопасность

- Пароль root от сервера и пароль панели лежат в `secrets/` — папка в `.gitignore`,
  права 600. Не публикуйте её.
- Рекомендую: сменить root-пароль сервера и добавить SSH-ключ вместо пароля
  (`~/.ssh/authorized_keys`), после чего отключить `PasswordAuthentication`.
- ufw режет всё, кроме 22/443/8443/2096. Панель — только через SSH-туннель.
- Обновление панели/ядра: `./rssh.sh 'x-ui update'` (см. `docs/ADMIN.md`).
