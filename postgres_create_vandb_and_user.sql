-- =====================================================================
-- Добавляет только роль vanuser и базу vandb на уже работающем PostgreSQL.
-- Другие базы в кластере не трогаются (не удаляются и не переименовываются).
-- =====================================================================
-- Выполнить под суперпользователем (часто postgres), например:
--   psql -h YOUR_SERVER_IP -U postgres -f postgres_create_vandb_and_user.sql
--
-- Перед запуском замените REPLACE_WITH_STRONG_PASSWORD на пароль для vanuser.

-- 1) Роль: можно выполнять повторно — если vanuser уже есть, новая роль не создаётся.
DO $body$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'vanuser') THEN
        CREATE ROLE vanuser WITH LOGIN PASSWORD 'REPLACE_WITH_STRONG_PASSWORD';
    END IF;
END
$body$;

-- 2) Новая база «рядом» с остальными (отдельное имя — vandb).
--    Если база уже есть, будет ошибка "already exists" — это нормально, шаг пропустите.
--    PostgreSQL 15+: можно заменить строку ниже на:
--    CREATE DATABASE IF NOT EXISTS vandb OWNER vanuser ENCODING 'UTF8' TEMPLATE template0;
CREATE DATABASE vandb OWNER vanuser ENCODING 'UTF8' TEMPLATE template0;

-- 3) Опционально (PostgreSQL 15+, жёсткие права на public): подключитесь к vandb и выдайте схему.
--    Только через psql (метакоманды), отдельным запуском:
--   \c vandb
--   GRANT ALL ON SCHEMA public TO vanuser;
--   ALTER DEFAULT PRIVILEGES FOR ROLE vanuser IN SCHEMA public GRANT ALL ON TABLES TO vanuser;
