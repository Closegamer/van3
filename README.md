# van3 — PostgreSQL в Docker (удалённый сервер)

Репозиторий для **развёртывания контейнера PostgreSQL** (`postgres:16-alpine`) с БД **`vandb`** и пользователем из `.env.docker`. CI/CD по push в `main`: SSH на сервер, обновление кода, `docker compose up -d`.

## Быстрый старт (сервер или локально)

1. `cp .env.docker.example .env.docker` — задайте **`POSTGRES_PASSWORD`**, при необходимости **`VAN_POSTGRES_PUBLISH`** (если порт 5432 занят — например `55432`).
2. `docker compose --env-file .env.docker up -d`
3. Проверка: `docker compose --env-file .env.docker ps` и `npm run check-db` (нужен `.env` с `VAN_DB_*`, см. `.env.example`).

Подробности: **`DEPLOY.md`** (ручной деплой по SSH, GitHub Actions, секреты).

## Полезное в репозитории

| Путь | Назначение |
|------|------------|
| `docker-compose.yml` | Сервис `postgres`, том данных |
| `.env.docker.example` | Шаблон переменных для compose |
| `scripts/deploy_remote.ps1` / `deploy_remote.sh` | Копирование compose + `.env.docker` на хост и `up -d` |
| `scripts/check_db_connection.mjs` | Проверка подключения к БД (`npm run check-db`) |
| `scripts/provision_vandb.mjs` + `sql/provision_vandb.sql` | Опционально: создание роли/БД на **уже существующем** кластере (админ) |
| `Makefile` | `make up` / `make logs` / `make status` |

## CI/CD

При пуше в **`main`**: валидация `docker compose config`, деплой по SSH (см. таблицу секретов в **`DEPLOY.md`**).

## Переменные для клиентов к этой БД

На любой машине, откуда подключаетесь к Postgres: в **`.env`** задайте **`VAN_DB_HOST`**, **`VAN_DB_PORT`** (как **`VAN_POSTGRES_PUBLISH`** на сервере), **`VAN_DB_PASSWORD`** = пароль роли в контейнере. См. **`.env.example`**.
