# van3 — VanSearch + PostgreSQL (vandb)

PowerShell-оркестратор `run_van.ps1`, учёт диапазонов в PostgreSQL, Docker-стек только с **Postgres** (`vandb`), импорт `completed.txt` в таблицу `yxxxxxx`.

## Локально

- `run_van.bat` / `run_van.ps1` — рядом нужны `VanSearch.exe`, опционально `.env` (см. `.env.example`).
- **Несколько ПК, одна PostgreSQL:** в `.env` задайте `VAN_DB_HOST`, `VAN_DB_PORT`, `VAN_DB_PASSWORD` (и при необходимости `VAN_WORKER_ID`). Режим базы включается сам; координация диапазонов — таблица `van_ranges` (см. **DEPLOY.md → Несколько машин**).
- Импорт в БД: `npm run import-completed` или `.\Import-CompletedToYxxxxxx.ps1`. При блокировке `.ps1` смотри **DEPLOY.md** (Bypass / `node scripts/...`). Первый раз с БД для **`run_van.ps1`**: добавь **`--van-ranges`** или **`-VanRanges`**.

## Docker

См. `DEPLOY.md`. Кратко: `cp .env.docker.example .env.docker`, правка пароля, `docker compose --env-file .env.docker up -d`.

## CI/CD (как у mdelayrepoplus)

При пуше в **`main`** GitHub Actions:

1. **CI** — проверка `docker compose config`, синтаксис Node-скриптов.
2. **Deploy** — SSH на сервер, `git clone` / `git fetch` + `reset --hard origin/main`, запись **`.env.docker`** из секретов, `docker compose up -d`.

### Секреты репозитория (Settings → Secrets → Actions)

Те же идеи, что в **mdelayrepoplus**:

| Секрет | Назначение |
|--------|------------|
| `DEPLOY_HOST` | IP/DNS сервера (например `YOUR_SERVER_IP`) |
| `DEPLOY_USER` | SSH-пользователь |
| `DEPLOY_SSH_KEY` | Приватный ключ (весь PEM) |
| `DEPLOY_SSH_KEY_PASSPHRASE` | Опционально: пароль от ключа, если при генерации задавался passphrase (иначе SSH в Actions не залогинится) |
| `DEPLOY_PORT` | SSH-порт; если не задать, в workflow используется `22` |
| `DEPLOY_APP_DIR` | Каталог на сервере (например `/opt/van3`) |
| `GH_REPO_TOKEN` | PAT с `repo` для `git clone` по HTTPS |

Отдельно для Postgres в Docker:

| Секрет | Назначение |
|--------|------------|
| `VAN_POSTGRES_USER` | Обычно `vanuser` |
| `VAN_POSTGRES_PASSWORD` | Пароль суперпользователя БД в контейнере |
| `VAN_POSTGRES_DB` | Обычно `vandb` |
| `VAN_POSTGRES_PUBLISH` | Порт **хоста** для Postgres (например `5432`). Если на сервере уже слушает другой Postgres — **другой порт**, напр. `55432`, и тот же порт в `VAN_DB_PORT` в `.env` у воркеров |

На сервере нужны **Git** и **Docker Compose v2** (`docker compose`).

### Первый пуш

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<USER>/<REPO>.git
git push -u origin main
```

PAT в `GH_REPO_TOKEN` должен иметь доступ к этому репозиторию.

## Переменные для `run_van.ps1` с удалённой БД

В `.env` на машине, где крутится поиск: `VAN_DB_HOST`, `VAN_DB_PORT` (как в `VAN_POSTGRES_PUBLISH`), `VAN_DB_PASSWORD` = тот же, что `VAN_POSTGRES_PASSWORD`, и т.д. (см. `.env.example`).
