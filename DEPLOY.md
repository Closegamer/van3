# Развёртывание PostgreSQL (vandb) в Docker

Стек автономен: образ `postgres:16-alpine`, том данных, при **первом** запуске создаются пользователь, БД `vandb` и таблицы `vanity_ranges`, `yxxxxxx` из `docker/initdb/`.

## Локально или на сервере (одинаково)

1. Скопируйте переменные: `cp .env.docker.example .env.docker`
2. Задайте надёжный `POSTGRES_PASSWORD` в `.env.docker`
3. При необходимости измените `VANITY_POSTGRES_PUBLISH` (например `127.0.0.1:5432`, чтобы не светить порт наружу)
4. Запуск:
   ```bash
   docker compose --env-file .env.docker up -d
   ```
5. Проверка: `docker compose --env-file .env.docker ps` и `docker compose --env-file .env.docker logs -f postgres`

На Linux удобно: `make up` / `make logs` (см. `Makefile`).

## Подключение `run_vanity.ps1`

В `.env` (рядом со скриптом) укажите хост, куда опубликован порт 5432:

- тот же компьютер: `VANITY_DB_HOST=127.0.0.1`
- удалённый сервер: `VANITY_DB_HOST=<IP_или_DNS>`

Пользователь и БД должны совпадать с `.env.docker`: обычно `vanuser` / `vandb`. Пароль — тот же, что `POSTGRES_PASSWORD` в `.env.docker` → в `.env` как `VANITY_DB_PASSWORD`.

Флаг `-DbInitSchema` при чистом Docker **не обязателен**: схема уже создана init-скриптом.

## Удалённое развёртывание

- **Windows (PowerShell):** `.\scripts\deploy_remote.ps1 -Target user@host -RemotePath /opt/van3`
- **Linux/macOS:** `chmod +x scripts/deploy_remote.sh && ./scripts/deploy_remote.sh user@host /opt/van3`

На сервере должен быть установлен Docker и plugin Compose v2. Файл `.env.docker` копируется с вашей машины (держите его вне git).

Если на сервере уже занят порт **5432** (другой Postgres), в `.env.docker` задайте, например, `VANITY_POSTGRES_PUBLISH=55432`, и в `.env` укажите `VANITY_DB_PORT=55432`.

## Импорт `completed.txt` → таблица `yxxxxxx`

Каждая непустая строка файла (без ведущего `#`) — одна строка в таблице `yxxxxxx` (`line_text`). Повторы в БД не дублируются (`ON CONFLICT DO NOTHING`).

```bash
npm run import-completed
# или
node scripts/import_completed_to_yxxxxxx.mjs --file completed.txt
```

Из PowerShell: `.\Import-CompletedToYxxxxxx.ps1` (по умолчанию `completed.txt` в каталоге проекта).

Подключение те же переменные, что для `run_vanity.ps1`: `VANITY_DB_*` в `.env`.

## GitHub Actions

Workflow `.github/workflows/ci-cd.yml` — при пуше в `main` (как в mdelayrepoplus): CI + деплой по SSH с пересборкой `.env.docker` из секретов. Список секретов — в `README.md`.

## Сброс данных

Том `van3_pgdata` сохраняет данные. Чтобы прогнать initdb заново:

```bash
docker compose --env-file .env.docker down
docker volume rm van3_pgdata
docker compose --env-file .env.docker up -d
```

**Внимание:** это удалит все строки в `vanity_ranges`.
