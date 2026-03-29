# Развёртывание PostgreSQL (vandb) в Docker

Стек автономен: образ `postgres:16-alpine`, том данных, при **первом** запуске создаются пользователь, БД `vandb` и таблицы `van_ranges`, `yxxxxxx` из `docker/initdb/`.

## Локально или на сервере (одинаково)

1. Скопируйте переменные: `cp .env.docker.example .env.docker`
2. Задайте надёжный `POSTGRES_PASSWORD` в `.env.docker`
3. При необходимости измените `VAN_POSTGRES_PUBLISH` (например `127.0.0.1:5432`, чтобы не светить порт наружу)
4. Запуск:
   ```bash
   docker compose --env-file .env.docker up -d
   ```
5. Проверка: `docker compose --env-file .env.docker ps` и `docker compose --env-file .env.docker logs -f postgres`

На Linux удобно: `make up` / `make logs` (см. `Makefile`).

## Подключение `run_van.ps1`

В `.env` (рядом со скриптом) укажите хост, куда опубликован порт 5432:

- тот же компьютер: `VAN_DB_HOST=127.0.0.1`
- удалённый сервер: `VAN_DB_HOST=<IP_или_DNS>`

Пользователь и БД должны совпадать с `.env.docker`: обычно `vanuser` / `vandb`. Пароль — тот же, что `POSTGRES_PASSWORD` в `.env.docker` → в `.env` как `VAN_DB_PASSWORD`.

Флаг `-DbInitSchema` при чистом Docker **не обязателен**: схема уже создана init-скриптом.

## Удалённое развёртывание

- **Windows (PowerShell):** `.\scripts\deploy_remote.ps1 -Target user@host -RemotePath /opt/van3`
- **Linux/macOS:** `chmod +x scripts/deploy_remote.sh && ./scripts/deploy_remote.sh user@host /opt/van3`

На сервере должен быть установлен Docker и plugin Compose v2. Файл `.env.docker` копируется с вашей машины (держите его вне git).

Если на сервере уже занят порт **5432** (другой Postgres), в `.env.docker` задайте, например, `VAN_POSTGRES_PUBLISH=55432`, и в `.env` укажите `VAN_DB_PORT=55432`.

## Импорт `completed.txt` → таблица `yxxxxxx`

Каждая непустая строка файла (без ведущего `#`) — одна строка в таблице `yxxxxxx` (`line_text`). Повторы в БД не дублируются (`ON CONFLICT DO NOTHING`).

```bash
npm run import-completed
# или
node scripts/import_completed_to_yxxxxxx.mjs --file completed.txt
```

Из PowerShell: `.\Import-CompletedToYxxxxxx.ps1` (по умолчанию `completed.txt` в каталоге проекта).

Подключение те же переменные, что для `run_van.ps1`: `VAN_DB_*` в `.env`.

## GitHub Actions (CI/CD)

Файл: `.github/workflows/ci-cd.yml`.

- **CI** — на каждый push и pull request в `main`: проверка `docker compose config`, синтаксис Node-скриптов.
- **Deploy** — только на **push** в `main` (не на PR): SSH на сервер, `git fetch` + `reset --hard`, запись `.env.docker` из секретов, `docker compose pull` (если доступно) и `up -d`.

### Чеклист настройки

1. **Сервер:** установлены Git, Docker и плагин Compose v2 (`docker compose`). Пользователь из `DEPLOY_USER` может писать в `DEPLOY_APP_DIR` (например `/opt/van3`) и запускать Docker.
2. **SSH:** в Actions-секрет `DEPLOY_SSH_KEY` вставьте **полный** приватный ключ (PEM), одной строкой с переносами как в файле. Публичный ключ — в `~/.ssh/authorized_keys` на сервере.
3. **PAT:** создайте [Personal Access Token](https://github.com/settings/tokens) с правом **Contents: Read** (или классический `repo` для приватного репозитория). Секрет **`GH_REPO_TOKEN`** — для `git clone`/`fetch` по HTTPS на сервере.
4. **Секреты** (Settings → Secrets and variables → Actions): заполните таблицу из `README.md`. Порт SSH: если не задан `DEPLOY_PORT`, в workflow подставляется **22**; для нестандартного порта задайте секрет явно.
5. **Первый деплой:** запушьте в `main` или запустите workflow вручную (**Actions** → **CI/CD** → **Run workflow**).

После деплоя на машине с `run_van.ps1` в `.env` укажите `VAN_DB_HOST` (IP/DNS сервера), `VAN_DB_PORT` (как опубликован Postgres, см. `VAN_POSTGRES_PUBLISH`), `VAN_DB_PASSWORD` = тот же пароль, что в секрете **`VAN_POSTGRES_PASSWORD`** (он же попадает в `POSTGRES_PASSWORD` в контейнере).

## Сброс данных

Том `van3_pgdata` сохраняет данные. Чтобы прогнать initdb заново:

```bash
docker compose --env-file .env.docker down
docker volume rm van3_pgdata
docker compose --env-file .env.docker up -d
```

**Внимание:** это удалит все строки в `van_ranges`.
