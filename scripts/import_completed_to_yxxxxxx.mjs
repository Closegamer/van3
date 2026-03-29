/**
 * Импорт строк из completed.txt в таблицу yxxxxxx (PostgreSQL).
 * Подключение из .env: VANITY_DB_HOST, VANITY_DB_PORT, VANITY_DB_NAME, VANITY_DB_USER, VANITY_DB_PASSWORD
 *
 *   node scripts/import_completed_to_yxxxxxx.mjs
 *   node scripts/import_completed_to_yxxxxxx.mjs --file path/to/completed.txt
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import pg from "pg";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const text = fs.readFileSync(filePath, "utf8");
  for (let line of text.split("\n")) {
    line = line.trim();
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf("=");
    if (i === -1) continue;
    const k = line.slice(0, i).trim();
    let v = line.slice(i + 1).trim();
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      v = v.slice(1, -1);
    }
    if (process.env[k] === undefined) process.env[k] = v;
  }
}

loadEnvFile(path.join(root, ".env"));

let fileArg = path.join(root, "completed.txt");
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--file" && process.argv[i + 1]) {
    fileArg = path.resolve(process.argv[++i]);
  }
}

const host = process.env.VANITY_DB_HOST || "127.0.0.1";
const port = Number(process.env.VANITY_DB_PORT || 5432);
const database = process.env.VANITY_DB_NAME || "vandb";
const user = process.env.VANITY_DB_USER || "vanuser";
const password = process.env.VANITY_DB_PASSWORD;

if (!password) {
  console.error("Нет VANITY_DB_PASSWORD в .env");
  process.exit(1);
}

if (!fs.existsSync(fileArg)) {
  console.error("Файл не найден:", fileArg);
  process.exit(1);
}

const raw = fs.readFileSync(fileArg, "utf8");
const lines = raw
  .split(/\r?\n/)
  .map((s) => s.trim())
  .filter((s) => s.length > 0 && !s.startsWith("#"));

if (lines.length === 0) {
  console.log("Нет непустых строк для импорта.");
  process.exit(0);
}

function sslOption() {
  const m = process.env.PGSSLMODE || "";
  if (m === "require" || m === "prefer")
    return { rejectUnauthorized: process.env.PGSSL_REJECT_UNAUTHORIZED !== "0" };
  return false;
}

const client = new pg.Client({
  host,
  port,
  user,
  password,
  database,
  ssl: sslOption(),
  connectionTimeoutMillis: 30000,
});

await client.connect();

await client.query(`
CREATE TABLE IF NOT EXISTS yxxxxxx (
    id BIGSERIAL PRIMARY KEY,
    line_text VARCHAR(256) NOT NULL,
    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_yxxxxxx_line_text UNIQUE (line_text)
);
`);
await client.query(`
CREATE INDEX IF NOT EXISTS ix_yxxxxxx_imported_at ON yxxxxxx (imported_at);
`);

let inserted = 0;
let skipped = 0;
for (const line of lines) {
  const t = line.length > 256 ? line.slice(0, 256) : line;
  try {
    const r = await client.query(
      `INSERT INTO yxxxxxx (line_text) VALUES ($1) ON CONFLICT (line_text) DO NOTHING`,
      [t]
    );
    if (r.rowCount > 0) inserted++;
    else skipped++;
  } catch (e) {
    console.error("Ошибка вставки:", t, e.message);
    throw e;
  }
}

await client.end();

console.log(
  `Импорт завершён: добавлено ${inserted}, уже были (пропуск) ${skipped}, всего строк в файле ${lines.length}.`
);
