-- Выполнить в SSMS или sqlcmd под учёткой с правами sysadmin.
-- Замените REPLACE_WITH_STRONG_PASSWORD перед выполнением.

CREATE DATABASE vandb;
GO

USE master;
GO

CREATE LOGIN vanuser WITH PASSWORD = N'REPLACE_WITH_STRONG_PASSWORD';
GO

USE vandb;
GO

CREATE USER vanuser FOR LOGIN vanuser;
GO

ALTER ROLE db_owner ADD MEMBER vanuser;
GO
