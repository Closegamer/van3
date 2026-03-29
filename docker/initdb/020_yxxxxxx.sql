-- Строки из completed.txt (каждая строка — отдельная запись).

CREATE TABLE IF NOT EXISTS yxxxxxx (
    id BIGSERIAL PRIMARY KEY,
    line_text VARCHAR(256) NOT NULL,
    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_yxxxxxx_line_text UNIQUE (line_text)
);

CREATE INDEX IF NOT EXISTS ix_yxxxxxx_imported_at ON yxxxxxx (imported_at);
