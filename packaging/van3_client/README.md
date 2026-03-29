# van3_client — воркер поиска

Минимальный набор для запуска **`run_van.ps1`** с **любой Windows-машины** против общего Postgres (таблица `van_ranges`).

## Подготовка

1. Положите рядом **`VanSearch.exe`** (в этот же каталог).
2. Установите **64-разрядный** ODBC-драйвер PostgreSQL: [odbc.postgresql.org](https://odbc.postgresql.org/) (на Windows часто нужен **psqlODBC** x64, не 32-bit). Откройте **«Администратор источников данных ODBC (64-разрядная)»** → вкладка «Драйверы» и проверьте имя (часто **`{PostgreSQL Unicode}`** или **`{PostgreSQL ANSI}`**). Если ошибка **IM002**, в `.env` добавьте строку **`VAN_ODBC_DRIVER={точное имя из списка}`**.
3. Скопируйте **`.env.example` → `.env`**, укажите **`VAN_DB_HOST`**, **`VAN_DB_PORT`**, **`VAN_DB_PASSWORD`** (как у сервера van3 / `POSTGRES_PASSWORD`). Порт часто не 5432 (см. `VAN_POSTGRES_PUBLISH` на сервере).

## Запуск

- Двойной щелчок **`run_van.bat`** или в PowerShell:
  ```powershell
  cd путь\к\van3_client
  powershell -NoProfile -ExecutionPolicy Bypass -File .\run_van.ps1
  ```

Политика выполнения: см. основной **DEPLOY.md** проекта van3 (`ExecutionPolicy Bypass` или `RemoteSigned`).

## Файлы в каталоге

| Файл           | Назначение |
|----------------|------------|
| `run_van.ps1`  | Оркестратор, БД, вызов `VanSearch.exe` |
| `run_van.bat`  | Запуск PowerShell с обходом политики |
| `.env`         | Секреты (создаёте вы; не пересылайте) |
| `started.txt`  | Создаётся скриптом — точка возобновления |
| `output.txt`   | Вывод поиска (если пишет VanSearch) |

Пройденные диапазоны хранятся **в БД** (`van_ranges`), локальный `completed.txt` по умолчанию не используется.

## Обновление скриптов

После `git pull` в репозитории **van3** снова запустите из корня van3:

`.\scripts\publish_van3_client.ps1`

Будет перезаписан каталог **`van3_client`** на уровень выше (рядом с **van3**). Ваши `.env` и `.exe` в **van3_client** скрипт не трогает.
