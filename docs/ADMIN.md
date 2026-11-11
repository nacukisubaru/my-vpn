# Администрирование

Все команды выполняются из папки проекта на Mac. Пароль/токены — в `secrets/`.

## Админка: URL, логин, пароль

| | |
|---|---|
| **URL** | `http://localhost:38217/lVsDniTvh17lDbpiAV/` |
| **Логин** | `admJgOJhmxfw` |
| **Пароль** | `WubkxKMe6GrZAV4CZWs3wGFK` |
| **API-токен** | `fQUwOl0eKn2eIm6Ytn8wJjgvZ4IbcL5hsr35ToGAD5WWVUac` |

```bash
./panel-tunnel.sh
# затем в браузере: http://localhost:38217/lVsDniTvh17lDbpiAV/
```

Панель слушает только `127.0.0.1` на сервере (`webListen=127.0.0.1`), поэтому без
туннеля она недоступна — это сделано намеренно. Порт панели `38217`, путь `/lVsDniTvh17lDbpiAV/`
(оба случайные — чтобы сканеры не находили панель даже при открытом порте).

### Открыть панель наружу (опционально)

Нужно, только если хотите заходить в админку с телефона/чужого компьютера без SSH-клиента.

Плюсы: не нужен терминал и `./panel-tunnel.sh`, можно с любого устройства.
Минусы: панель становится видна сканерам (боты брутфорсят 3x-ui круглосуточно),
трафик логина идёт по **HTTP без TLS** (пароль в открытом виде внутри страны), и это
дополнительная точка атаки на сервер, где живёт ваш VPN.

Если всё же нужно:

```bash
# 1) вернуть панель на все интерфейсы
./rssh.sh '/usr/local/x-ui/x-ui setting -listenIP 0.0.0.0 && systemctl restart x-ui'

# 2) открыть порт в фаерволе (или сначала спрятать за VPN — см. вариант Б)
./rssh.sh 'ufw allow 38217/tcp'

# 3) проверить
curl -s -o /dev/null -w "%{http_code}\n" http://82.148.226.31:38217/lVsDniTvh17lDbpiAV/
```

**Вариант Б (безопаснее):** оставить панель на `127.0.0.1` и ходить в неё с телефона
через VPN — включите на телефоне VPN-профиль и откройте
`http://127.0.0.1:38217/lVsDniTvh17lDbpiAV/`… не сработает (это localhost телефона).
Поэтому правильнее: на сервере поставить Caddy/nginx с TLS-сертификатом на домен и
проксировать панель через него — тогда наружу торчит только HTTPS.

Откатить обратно (рекомендуется после использования):

```bash
./rssh.sh '/usr/local/x-ui/x-ui setting -listenIP 127.0.0.1 && systemctl restart x-ui && ufw delete allow 38217/tcp'
```

## API без браузера

```bash
./xui-api.sh GET  /panel/api/inbounds/list
./xui-api.sh POST /panel/api/clients/add payload.json
```

Токен: `secrets/panel.json` → `api_token`. Перевыпустить (старый станет невалидным):

```bash
./rssh.sh '/usr/local/x-ui/x-ui setting -getApiToken'
```

## Добавить клиента (себе на телефон, другу)

### Через панель
`Inbounds` → `VLESS-Reality-443` → `+` (Add client) → Email (любое имя), Flow `xtls-rprx-vision`
→ Save. Ссылку взять в строке клиента (`QR`/`Copy link`).

### Через API

```bash
cat > /tmp/client.json <<'JSON'
{
  "client": {
    "id": "СГЕНЕРИРОВАТЬ-UUID-v4",
    "flow": "xtls-rprx-vision",
    "email": "phone",
    "limitIp": 0,
    "totalGB": 0,
    "expiryTime": 0,
    "enable": true,
    "subId": "phonesub01"
  },
  "inboundIds": [1]
}
JSON
./xui-api.sh POST /panel/api/clients/add /tmp/client.json
./xui-api.sh GET  /panel/api/clients/links/phone     # готовые vless:// ссылки
```

UUID v4 можно сгенерировать локально: `python3 -c "import uuid;print(uuid.uuid4())"`.
Ограничения: `totalGB` — лимит трафика (0 = безлимит), `expiryTime` — timestamp в мс (0 = бессрочно).

Удалить клиента: `./xui-api.sh POST /panel/api/clients/del/phone`.

3x-ui v3 применяет изменения «на лету» через API ядра — xray не перезапускается,
существующие подключения не рвутся.

## Резервный вход :8443 (уже настроен)

| | Вход 443 (основной) | Вход 8443 (резерв) |
|---|---|---|
| Inbound id | 1 (`VLESS-Reality-443`) | 2 (`VLESS-Reality-8443-backup`) |
| SNI / dest | `cdn.jsdelivr.net` | `www.python.org` |
| publicKey | `OU0AvToZSJPrfppeSQ7R3k_Bo3dwO-UBzmkmNL72FTM` | `GhlACaIyiC5RmlMaHQn77shBcpeeFZxqbNk-T_efDgc` |
| shortId | `17ccf52039c254df` | `ced31a3dfc59cb94` |
| Клиенты | `main`, `phone` | `backup`, `phone` |

Зачем: если 443 начнут резать или заблокируют SNI, в клиенте достаточно переключиться на
второй профиль — ничего перенастраивать не нужно. Оба профиля приходят в подписке
`.../phonesub01`.

Проверить оба входа сразу:

```bash
./test-both.sh
```

Выключить/включить резерв (например, чтобы не светить лишний порт):

```bash
./xui-api.sh POST /panel/api/inbounds/setEnable/2   # toggle
./rssh.sh 'ufw allow 8443/tcp'    # или: ufw delete allow 8443/tcp
```

## Клиент для телефона (уже настроен)

Отдельный UUID `3def1d1b-8431-4f46-a65d-40c1b6b4e4d4`, email `phone`, подписка
`http://82.148.226.31:2096/4zbxad4mwilt8wjw/phonesub01`, QR — в `qr/phone-443.png`
и `qr/phone-8443.png`.

Почему отдельный клиент, а не общий: можно в любой момент отозвать телефон
(`./xui-api.sh POST /panel/api/clients/del/phone`), не трогая ПК, и видеть его трафик отдельно
в панели (`sqlite3 /etc/x-ui/x-ui.db "select email,up,down from client_traffics"`).

## Сменить dest/SNI (если начнут фильтровать домен)

SNI — это домен, под который маскируется туннель. Требования к кандидату:
TLS 1.3 + HTTP/2 поддерживаются, домен не заблокирован в РФ, стабильно доступен с сервера.

```bash
./rotate.sh                           # случайный SNI из пула + новые ключи (рекомендуется)
./rotate.sh --sni www.python.org      # вручную задать SNI
./rotate.sh --without-sni             # только ключи, SNI не трогать
./rotate.sh --change-port             # ещё и случайный порт
```

Полное описание флагов, карантина и пула — [ROTATION.md](ROTATION.md).

`rotate.sh` перед изменением делает снапшот в `docs/snapshots/<дата>_<время>-rotate/`, проверяет
домен (TLS 1.3 + h2) и меняет: `privateKey`, `shortIds`, `dest`/`serverNames`, при необходимости порт.
Затем сам вызывает `sync-client.sh`, который пересобирает `client/*.json`, ссылки, QR и `secrets/vpn.json`.

В обоих случаях старые профили на устройствах перестают работать — нужно переимпортировать
ссылку/подписку. Откат: `./rollback.sh <снапшот>` ([docs/ROLLBACK.md](ROLLBACK.md)).

Проверенные кандидаты с этого сервера (TLS 1.3 + h2, стабильны):

| Домен | Замечание |
|---|---|
| `cdn.jsdelivr.net` | **текущий для :443**, точное совпадение (CN=*.jsdelivr.net), стабилен v4/v6 |
| `www.apple.com` | использовался до 2026-11-05, стабилен, но Apple-домены в РФ на особом контроле |
| `www.bing.com` | быстрый, но сертификат на `r.bing.com` (визуальная нестыковка) |
| `dl.google.com` | Google, но в РФ google-домены под давлением |
| `www.samsung.com` | по v6 с этого сервера нестабилен |
| `www.microsoft.com` | нестабильный IPv6-путь с этого сервера (были обрывы) |

Ручной вариант (без скрипта): поправить `dest`/`serverNames` в инбаунде через панель или
`./xui-api.sh POST /panel/api/inbounds/update/1 <json>` (шаблон: `artifacts/inbound-update.json`).

## Бэкап и восстановление

```bash
./backup.sh                      # сохранит БД в backups/x-ui-<дата>.db
```

Восстановление:

```bash
./rssh.sh -f backups/x-ui-2026-11-04_1200.db 'cat > /etc/x-ui/x-ui.db'
./rssh.sh 'systemctl restart x-ui'
```

## Обновление 3x-ui / Xray

```bash
./rssh.sh 'x-ui update'          # обновит панель и ядро Xray
./rssh.sh 'x-ui status'
```

После обновления прогнать `./test-tunnel.sh` — конфиг inbound'а сохраняется.

## Перезагрузка сервера

`x-ui.service` включён в автозапуск, ufw-правила применяются при старте.
Проверка после ребута: `./test-tunnel.sh`.

## Диагностика

```bash
./diag.sh                                                # послойная диагностика + вердикт
./rotate.sh --list-sni                                   # пул SNI и статусы
./rotate.sh --list-ports                                 # пул портов
./rssh.sh 'x-ui status'                                  # панель
./rssh.sh 'x-ui log'                                     # лог ядра/панели
./rssh.sh 'journalctl -u x-ui --since "-15min" --no-pager | tail -50'
./rssh.sh 'ss -tulpn | grep -E ":443|:38217|:2096"'       # порты
./rssh.sh 'ufw status verbose'                           # фаервол
./rssh.sh 'sqlite3 /etc/x-ui/x-ui.db "select email,enable,up,down from client_traffics"'   # трафик клиентов
./test-tunnel.sh                                         # сквозная проверка
```

Проверка маскировки снаружи (с любого хоста):

```bash
echo | openssl s_client -connect 82.148.226.31:443 -servername cdn.jsdelivr.net -tls1_3 -alpn h2 2>/dev/null \
  | grep -E "subject=|ALPN"
# должно быть: CN=*.jsdelivr.net и ALPN protocol: h2
```

### Типовые проблемы

| Симптом | Причина / что делать |
|---|---|
| Клиент не подключается, сервер жив | Сверить `pbk`/`sid`/`sni`/`fp` со ссылкой из `client/vless-*.txt`; чаще всего профиль на устройстве остался от старой ротации ключей → переимпортировать |
| Подключается, но нет интернета | Клиент «включён», но режим прокси выключен; либо DNS клиента: включить `remote DNS` / `socks5h` |
| Часть сайтов не грузится | Проверить `./rssh.sh 'x-ui log'`: dest недоступен с сервера → сменить dest (`./change-dest.sh`) |
| Низкая скорость | 1 vCPU: ограничение шифрования. Смотреть `top` на сервере; можно включить `mux` в клиенте или сменить хостинг на 2+ vCPU |
| После обновления конфиг сломался | `./rssh.sh 'x-ui log'`, при необходимости откатить БД из `backups/` |

## Что можно улучшить (по желанию)

1. ~~Второй inbound-резерв~~ — **сделано**: `VLESS-Reality-8443-backup` на :8443 (см. выше).
2. **Post-quantum Reality** (`x25519mlkem768`): в inbound'е Reality добавить `mldsa65Seed`
   (панель генерирует), клиенты Xray ≥ 25 поддерживают автоматически.
3. **Панель с TLS**: получить домен, повесить Caddy/nginx на 443-подобный порт, панель — за ним.
4. **SSH только по ключу** (вход по паролю отключается — подробно ниже).
5. **Мониторинг**: `x-ui` умеет Telegram-бота (Настройки → Telegram) — уведомления о трафике/сбоях.

## Полное удаление

```bash
./rssh.sh 'x-ui uninstall'
```
(снесёт панель, xray и базу; ufw-правила останутся — при необходимости `ufw --force reset`).

## Про вход по SSH-ключу вместо пароля (пояснение)

Сейчас на сервер можно зайти `root` + пароль. Это удобно, но пароль можно подобрать
(боты круглосуточно перебирают SSH) и он лежит у вас в `secrets/server.json` открытым текстом.

**SSH-ключ** — это пара файлов: приватный (остаётся у вас на Mac, `~/.ssh/id_ed25519`,
никому не передаётся) и публичный (кладётся на сервер в `/root/.ssh/authorized_keys`).
Сервер пускает только того, у кого есть приватный файл. Подобрать его практически нельзя,
поэтому после настройки пароль можно отключить — и брутфорс перестаёт работать.

Смысл для вас: даже если пароль из этого проекта «утечёт», зайти на сервер не смогут.

Как включить (по желанию, 3 команды):

```bash
# 1) создать ключ на Mac (если ещё нет; Enter на все вопросы — без пароля на ключ или с ним)
ssh-keygen -t ed25519 -C "macbook" -f ~/.ssh/id_ed25519

# 2) положить публичный ключ на сервер
./rssh.sh 'mkdir -p /root/.ssh && chmod 700 /root/.ssh'
cat ~/.ssh/id_ed25519.pub | ./rssh.sh 'cat >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys'

# 3) проверить, что вход по ключу работает
ssh -o PreferredAuthentications=publickey root@82.148.226.31 'echo key-ok'
```

Только после того, как пункт 3 вернул `key-ok`, можно отключить пароль:

```bash
./rssh.sh 'sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config && systemctl reload ssh'
```

Если что-то пойдёт не так — у вас останется доступ через панель хостинга (Aeza) к консоли
VM, где можно вернуть `PasswordAuthentication yes`.

## Про открытие панели наружу (пояснение)

Панель — это веб-интерфейс управления VPN (добавить/удалить клиентов, смотреть трафик).
Сейчас она доступна **только через SSH-туннель**, потому что слушает `127.0.0.1`.

Если открыть её наружу (`ufw allow 38217/tcp` + `listenIP 0.0.0.0`):

- **Плюс:** можно зайти в админку с телефона или с любого чужого компьютера, без SSH-клиента
  и без `./panel-tunnel.sh` — просто открыть ссылку в браузере.
- **Минус 1:** порт видят сканеры интернета, боты 3x-ui брутфорсят логин постоянно
  (fail2ban тут не установился — блокировки нет, только встроенный лимит попыток).
- **Минус 2:** без TLS логин и пароль идут по HTTP — в открытом виде.
- **Минус 3:** больше поверхности атаки на сервер, где живёт ваш VPN.

Поэтому: держать закрытой, а если очень нужно с телефона — либо через VPN-туннель
с ноутбука, либо поднять Caddy с доменом и TLS и проксировать панель через него (тогда
наружу торчит обычный HTTPS). Для «просто посмотреть с телефона» обычно хватает
Telegram-бота 3x-ui (Настройки → Telegram): он показывает трафик/клиентов без веб-панели.
