/**
 * Одноразовая проверка: читает ../.env и делает SELECT 1.
 *   node scripts/check_db_connection.mjs
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

const host = (process.env.VAN_DB_HOST || "127.0.0.1").trim();
const port = Number((process.env.VAN_DB_PORT || "5432").trim());
const database = (process.env.VAN_DB_NAME || "vandb").trim();
const user = (process.env.VAN_DB_USER || "vanuser").trim();
const password = (process.env.VAN_DB_PASSWORD || "").trim();

if (!password) {
  console.error("Нет VAN_DB_PASSWORD в .env");
  process.exit(1);
}

console.log(
  `Подключение: ${user}@${host}:${port}/${database} (длина пароля ${password.length})`
);

const client = new pg.Client({
  host,
  port,
  user,
  password,
  database,
  connectionTimeoutMillis: 20000,
});

try {
  await client.connect();
  const r = await client.query(
    "select current_database() as db, current_user as role, 1 as ok"
  );
  console.log("Успех:", r.rows[0]);
} catch (e) {
  console.error("Ошибка:", e.message);
  process.exit(1);
} finally {
  await client.end().catch(() => {});
}
