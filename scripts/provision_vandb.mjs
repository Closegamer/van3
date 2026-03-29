/**
 * Создаёт роль vanuser (если нет) и БД vandb в PostgreSQL.
 *
 * Запуск из корня проекта:
 *   node scripts/provision_vandb.mjs
 *
 * Читает `.env`: VANITY_PG_ADMIN_* (и при необходимости VANITY_DB_* для хоста/порта).
 * Опционально: --env-file PATH --host IP (перекрывают .env).
 *
 * Пароль vanuser: VANITY_DB_PASSWORD / VANUSER_PASSWORD, иначе генерируется и печатается один раз.
 */
import fs from "fs";
import path from "path";
import pg from "pg";

function loadEnvFile(filePath, override = false) {
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
    if (override || process.env[k] === undefined) process.env[k] = v;
  }
}

const rootEnv = path.join(process.cwd(), ".env");
if (fs.existsSync(rootEnv)) {
  loadEnvFile(rootEnv, false);
}

let cliHost = null;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--env-file" && process.argv[i + 1]) {
    loadEnvFile(process.argv[++i], true);
  } else if (process.argv[i] === "--host" && process.argv[i + 1]) {
    cliHost = process.argv[++i];
  }
}

function adminHost() {
  const h =
    cliHost ||
    process.env.VANITY_PG_ADMIN_HOST ||
    process.env.VANITY_DB_HOST ||
    process.env.PGHOST ||
    process.env.POSTGRES_HOST ||
    null;
  if (!h || h === "db") return "YOUR_SERVER_IP";
  return h;
}

const host = adminHost();
const port = Number(
  process.env.VANITY_PG_ADMIN_PORT ||
    process.env.VANITY_DB_PORT ||
    process.env.PGPORT ||
    process.env.POSTGRES_PORT ||
    5432
);
const adminUser =
  process.env.VANITY_PG_ADMIN_USER ||
  process.env.PGUSER ||
  process.env.POSTGRES_USER ||
  "postgres";
const adminPass =
  process.env.VANITY_PG_ADMIN_PASSWORD ||
  process.env.PGPASSWORD ||
  process.env.POSTGRES_PASSWORD;

let vanPass =
  process.env.VANITY_DB_PASSWORD || process.env.VANUSER_PASSWORD || null;

function randomPass() {
  const b = Buffer.allocUnsafe(16);
  for (let i = 0; i < b.length; i++) b[i] = Math.floor(Math.random() * 256);
  return b.toString("hex");
}

if (!adminPass) {
  console.error(
    "Задайте VANITY_PG_ADMIN_PASSWORD в .env (или PGPASSWORD / POSTGRES_PASSWORD для совместимости)."
  );
  process.exit(1);
}

function sslOption() {
  const m = process.env.PGSSLMODE || "";
  if (m === "require" || m === "prefer")
    return { rejectUnauthorized: process.env.PGSSL_REJECT_UNAUTHORIZED !== "0" };
  return false;
}

async function connectAs(dbName) {
  const c = new pg.Client({
    host,
    port,
    user: adminUser,
    password: adminPass,
    database: dbName,
    ssl: sslOption(),
    connectionTimeoutMillis: 60000,
  });
  await c.connect();
  return c;
}

const appDb =
  process.env.VANITY_PG_ADMIN_DATABASE || process.env.POSTGRES_DB || null;
const tryDbs =
  appDb && appDb !== "postgres" ? [appDb, "postgres"] : ["postgres"];
let admin;
let lastErr = null;
for (const dbName of tryDbs) {
  try {
    admin = await connectAs(dbName);
    if (dbName !== "postgres") {
      console.error("(Сессия админа через БД", dbName + ".)");
    }
    break;
  } catch (e) {
    lastErr = e;
    console.error("Подключение к", dbName, ":", e.message);
  }
}
if (!admin) {
  throw lastErr || new Error("Не удалось подключиться к PostgreSQL.");
}

function pgQuoteLiteral(s) {
  return "'" + String(s).replace(/'/g, "''") + "'";
}

try {
  const { rows: roles } = await admin.query(
    "SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = $1",
    ["vanuser"]
  );
  if (roles.length === 0) {
    if (!vanPass) {
      vanPass = randomPass();
    }
    await admin.query(
      `CREATE ROLE vanuser WITH LOGIN PASSWORD ${pgQuoteLiteral(vanPass)}`
    );
    if (process.env.VANITY_DB_PASSWORD || process.env.VANUSER_PASSWORD) {
      console.log("Создана роль vanuser (пароль из env).");
    } else {
      console.log("Создана роль vanuser. Укажите в .env VANITY_DB_PASSWORD:");
      console.log(vanPass);
    }
  } else {
    console.log("Роль vanuser уже есть (пароль не менялся).");
  }

  const { rows: dbs } = await admin.query(
    "SELECT 1 FROM pg_database WHERE datname = $1",
    ["vandb"]
  );
  if (dbs.length === 0) {
    await admin.query(
      "CREATE DATABASE vandb OWNER vanuser ENCODING 'UTF8' TEMPLATE template0"
    );
    console.log("Создана БД vandb (владелец vanuser).");
  } else {
    console.log("БД vandb уже существует.");
  }
} finally {
  await admin.end();
}

console.log("Готово.");
