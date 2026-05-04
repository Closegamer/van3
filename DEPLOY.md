# Развёртывание PostgreSQL в Docker

Стек: образ **`postgres:16-alpine`**, именованный том данных. Пользователь, БД и пароль задаются переменными **`POSTGRES_*`** в **`.env.docker`**. Порт на хосте — **`VAN_POSTGRES_PUBLISH`**.

Опционально при **первом** создании тома можно смонтировать SQL в контейнер: раскомментируйте строку с **`docker/initdb`** в **`docker-compose.yml`** и положите скрипты в **`docker/initdb/`**.

## Локально или на сервере

1. `cp .env.docker.example .env.docker`
2. Задайте надёжный **`POSTGRES_PASSWORD`**
3. При необходимости измените **`VAN_POSTGRES_PUBLISH`** (например `127.0.0.1:5432`, чтобы не слушать все интерфейсы, или `55432`, если 5432 занят)
4. Запуск:
   ```bash
   docker compose --env-file .env.docker up -d
   ```
5. Проверка: `docker compose --env-file .env.docker ps` и `docker compose --env-file .env.docker logs -f postgres`

На Linux: **`make up`** / **`make logs`** (см. **`Makefile`**).

## Подключение приложений

Параметры подключения к Postgres должны совпадать с **`.env.docker`**:

- пользователь: **`POSTGRES_USER`** (по умолчанию `vanuser`)
- БД: **`POSTGRES_DB`** (по умолчанию `vandb`)
- пароль: **`POSTGRES_PASSWORD`**
- хост/порт: адрес сервера и порт из **`VAN_POSTGRES_PUBLISH`**

Локальная проверка с ПК: скопируйте **`.env.example`** в **`.env`**, заполните **`VAN_DB_*`**, выполните **`npm install`** и **`npm run check-db`**.

## Удалённое развёртывание (вручную)

- **Windows (PowerShell):** `.\scripts\deploy_remote.ps1 -Target user@host -RemotePath /opt/van3`
- **Linux/macOS:** `chmod +x scripts/deploy_remote.sh && ./scripts/deploy_remote.sh user@host /opt/van3`

На сервере нужны **Docker** и **Compose v2**. Файл **`.env.docker`** не коммитьте; скрипты копируют его вместе с **`docker-compose.yml`**.

## Админ: отдельный кластер без Docker

Если Postgres уже установлен и нужны только роль **`vanuser`** и БД **`vandb`**, см. **`sql/provision_vandb.sql`** (замените пароль в файле) или **`node scripts/provision_vandb.mjs`** с переменными **`VAN_PG_ADMIN_*`** (см. **`.env.example`**).

## GitHub Actions (CI/CD)

Файл: **`.github/workflows/ci-cd.yml`**.

- **CI** — на push и PR в `main`: проверка `docker compose config`, синтаксис **`scripts/check_db_connection.mjs`** и **`scripts/provision_vandb.mjs`**.
- **Deploy** — только на **push** в `main`: SSH на сервер, `git fetch` + `reset --hard`, запись **`.env.docker`** из секретов, `docker compose pull` (если доступно) и **`up -d`**.

### Секреты репозитория

| Секрет | Назначение |
|--------|------------|
| `DEPLOY_HOST` | IP/DNS сервера |
| `DEPLOY_USER` | SSH-пользователь |
| `DEPLOY_SSH_KEY` | Приватный ключ (PEM) |
| `DEPLOY_SSH_KEY_PASSPHRASE` | Опционально, если у ключа есть passphrase |
| `DEPLOY_PORT` | SSH-порт (по умолчанию в workflow: 22) |
| `DEPLOY_APP_DIR` | Абсолютный каталог на сервере (например `/home/deploy/apps/van3`) |
| `GH_REPO_TOKEN` | PAT с доступом `repo` для `git clone`/`fetch` по HTTPS |
| `VAN_POSTGRES_USER` | Обычно `vanuser` |
| `VAN_POSTGRES_PASSWORD` | Пароль суперпользователя БД в контейнере |
| `VAN_POSTGRES_DB` | Обычно `vandb` |
| `VAN_POSTGRES_PUBLISH` | Порт хоста для Postgres (например `5432` или `55432`) |

Чеклист SSH-ключа и PAT — как в прежней версии документации (генерация ключа, `authorized_keys`, права на каталог деплоя, `docker` без sudo для пользователя SSH).

**Ошибка `port is already allocated`:** на хосте занят порт из **`VAN_POSTGRES_PUBLISH`**. Задайте в секретах другой порт (например **`55432`**) и используйте тот же порт в клиентских **`VAN_DB_PORT`**. На сервере: `ss -tlnp | grep 5432`.

## Сброс данных

```bash
docker compose --env-file .env.docker down
docker volume rm van3_pgdata
docker compose --env-file .env.docker up -d
```

**Внимание:** удаляются все данные в томе PostgreSQL.
