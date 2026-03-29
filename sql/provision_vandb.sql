-- Создание роли vanuser и БД vandb на том же кластере PostgreSQL.
-- Перед запуском замените CHANGE_VANUSER_PASSWORD_HERE на пароль (тот же, что VAN_DB_PASSWORD в .env).
--
-- Пример с сервера, где уже есть psql и доступ суперпользователя:
--   psql -h HOST -U ADMIN_USER -d postgres -f sql/provision_vandb.sql

DO $body$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'vanuser') THEN
    EXECUTE format('CREATE ROLE vanuser WITH LOGIN PASSWORD %L', 'CHANGE_VANUSER_PASSWORD_HERE');
  END IF;
END
$body$;

CREATE DATABASE vandb OWNER vanuser ENCODING 'UTF8' TEMPLATE template0;
