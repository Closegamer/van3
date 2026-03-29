/**
 * Импорт строк из completed.txt в PostgreSQL:
 *   - таблица yxxxxxx (каждая строка файла — line_text);
 *   - опционально van_ranges (ключи длиной X для run_van.ps1, статус completed).
 *
 * Подключение из .env: VAN_DB_HOST, VAN_DB_PORT, VAN_DB_NAME, VAN_DB_USER, VAN_DB_PASSWORD
 *
 *   node scripts/import_completed_to_yxxxxxx.mjs
 *   node scripts/import_completed_to_yxxxxxx.mjs --file path/to/completed.txt
 *   node scripts/import_completed_to_yxxxxxx.mjs --van-ranges
 *   node scripts/import_completed_to_yxxxxxx.mjs --van-ranges --x-length 6
 *
 * VAN_IMPORT_WORKER_ID — worker_id для строк van_ranges (по умолчанию completed-txt-import).
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
let vanRanges = false;
let xLength = 6;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--file" && process.argv[i + 1]) {
    fileArg = path.resolve(process.argv[++i]);
  } else if (process.argv[i] === "--van-ranges") {
    vanRanges = true;
  } else if (process.argv[i] === "--x-length" && process.argv[i + 1]) {
    xLength = parseInt(process.argv[++i], 10);
    if (Number.isNaN(xLength) || xLength < 1 || xLength > 32) {
      console.error("--x-length: ожидается число от 1 до 32");
      process.exit(1);
    }
  }
}

const host = (process.env.VAN_DB_HOST || "127.0.0.1").trim();
const port = Number((process.env.VAN_DB_PORT || "5432").trim());
const database = (process.env.VAN_DB_NAME || "vandb").trim();
const user = (process.env.VAN_DB_USER || "vanuser").trim();
const password = (process.env.VAN_DB_PASSWORD || "").trim();

if (!password) {
  console.error("Нет VAN_DB_PASSWORD в .env (или пустая строка после trim).");
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
  const st = fs.statSync(fileArg);
  console.error(
    "Нет непустых строк для импорта. Файл:",
    fileArg,
    `(${st.size} байт). Строки с # в начале и пустые отбрасываются. Укажите путь: --file D:\\path\\completed.txt`
  );
  process.exit(1);
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

const hexKeyRe = new RegExp(`^[0-9A-F]{${xLength}}$`, "i");
const vanWorkerId =
  (process.env.VAN_IMPORT_WORKER_ID || "completed-txt-import").trim().slice(0, 128) ||
  "completed-txt-import";

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

let vanInserted = 0;
if (vanRanges) {
  const seen = new Set();
  const keys = [];
  for (const line of lines) {
    const u = line.trim().toUpperCase();
    if (!hexKeyRe.test(u) || seen.has(u)) continue;
    seen.add(u);
    keys.push(u);
  }

  await client.query(`
CREATE TABLE IF NOT EXISTS van_ranges (
    range_key VARCHAR(32) NOT NULL PRIMARY KEY,
    status VARCHAR(20) NOT NULL,
    prefix_index INT NOT NULL DEFAULT 0,
    worker_id VARCHAR(128) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP)
);
`);
  await client.query(`
CREATE INDEX IF NOT EXISTS ix_van_ranges_status ON van_ranges (status);
`);

  const chunk = 1500;
  for (let i = 0; i < keys.length; i += chunk) {
    const part = keys.slice(i, i + chunk);
    const r = await client.query(
      `INSERT INTO van_ranges (range_key, status, prefix_index, worker_id)
       SELECT UPPER(trim(x)), 'completed', 0, $2::varchar(128)
       FROM unnest($1::text[]) AS t(x)
       ON CONFLICT (range_key) DO NOTHING`,
      [part, vanWorkerId]
    );
    vanInserted += r.rowCount ?? 0;
  }
}

await client.end();

console.log(
  `Импорт yxxxxxx: добавлено ${inserted}, пропуск (уже были) ${skipped}, строк в файле ${lines.length}.`
);
if (vanRanges) {
  console.log(
    `Импорт van_ranges (completed, длина ключа ${xLength}): вставлено новых ${vanInserted} (конфликт — без изменений).`
  );
}
