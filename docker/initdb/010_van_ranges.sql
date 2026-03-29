-- Выполняется при первом старте контейнера (пустой volume), в БД POSTGRES_DB (vandb).

CREATE TABLE IF NOT EXISTS van_ranges (
    range_key VARCHAR(32) NOT NULL PRIMARY KEY,
    status VARCHAR(20) NOT NULL,
    prefix_index INT NOT NULL DEFAULT 0,
    worker_id VARCHAR(128) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP)
);

CREATE INDEX IF NOT EXISTS ix_van_ranges_status ON van_ranges (status);
