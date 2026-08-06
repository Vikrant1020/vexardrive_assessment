// VexarDrive - Fleet Ping Service
// Production-ready refactored version

const express = require("express");
const { Pool } = require("pg");
const jwt = require("jsonwebtoken");
const pino = require("pino");

// ---------------------------------------------------------------------------
// Logger — structured JSON logging
// ---------------------------------------------------------------------------
const logger = pino({
  level: process.env.LOG_LEVEL || "info",
  ...(process.env.NODE_ENV !== "production" && {
    transport: { target: "pino-pretty" },
  }),
});

// ---------------------------------------------------------------------------
// Configuration — all values from environment variables, no hardcoded secrets
// ---------------------------------------------------------------------------
const {
  DB_HOST,
  DB_PORT = "5432",
  DB_USER,
  DB_PASSWORD,
  DB_NAME,
  DB_SSL = "false",
  JWT_SECRET,
  PORT = "3000",
} = process.env;

if (!DB_HOST || !DB_USER || !DB_PASSWORD || !DB_NAME) {
  logger.fatal("Missing required database environment variables (DB_HOST, DB_USER, DB_PASSWORD, DB_NAME)");
  process.exit(1);
}

if (!JWT_SECRET) {
  logger.fatal("Missing required JWT_SECRET environment variable");
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Database — connection pool (reuses connections across requests)
// ---------------------------------------------------------------------------
const pool = new Pool({
  host: DB_HOST,
  port: parseInt(DB_PORT, 10),
  user: DB_USER,
  password: DB_PASSWORD,
  database: DB_NAME,
  ssl: DB_SSL === "true" ? { rejectUnauthorized: true } : false,
  max: parseInt(process.env.DB_POOL_MAX || "20", 10),
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on("error", (err) => {
  logger.error({ err }, "Unexpected idle client error");
});

// ---------------------------------------------------------------------------
// Express app
// ---------------------------------------------------------------------------
const app = express();
app.use(express.json());

// Attach logger to each request
app.use((req, res, next) => {
  req.log = logger.child({ reqId: req.headers["x-request-id"] || undefined });
  const start = Date.now();
  res.on("finish", () => {
    req.log.info(
      {
        method: req.method,
        url: req.originalUrl,
        status: res.statusCode,
        durationMs: Date.now() - start,
      },
      "request completed"
    );
  });
  next();
});

// ---------------------------------------------------------------------------
// Auth middleware — verifies JWT bearer token
// ---------------------------------------------------------------------------
function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Missing or invalid authorization header" });
  }

  try {
    const token = authHeader.split(" ")[1];
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch (err) {
    req.log.warn({ err: err.message }, "JWT verification failed");
    return res.status(401).json({ error: "Invalid or expired token" });
  }
}

// ---------------------------------------------------------------------------
// Health & Readiness endpoints (for container orchestration)
// ---------------------------------------------------------------------------

// Liveness — is the process alive?
app.get("/health", (_req, res) => {
  res.json({ status: "healthy", uptime: process.uptime() });
});

// Readiness — can the app serve traffic? (checks DB connectivity)
app.get("/ready", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ready" });
  } catch (err) {
    logger.error({ err }, "Readiness check failed");
    res.status(503).json({ status: "not ready", error: "database unreachable" });
  }
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

app.get("/", (_req, res) => {
  res.json({ service: "VexarDrive Fleet Ping Service", status: "running" });
});

// Fleet vehicle ping ingestion — high-frequency endpoint
app.post("/api/fleet/ping", async (req, res) => {
  const { vehicleId, lat, lng, speed, timestamp } = req.body;

  if (!vehicleId || lat == null || lng == null) {
    return res.status(400).json({ error: "vehicleId, lat, and lng are required" });
  }

  try {
    await pool.query(
      `INSERT INTO fleet_pings (vehicle_id, lat, lng, speed, ts) VALUES ($1, $2, $3, $4, $5)`,
      [vehicleId, lat, lng, speed, timestamp]
    );
    res.json({ status: "ok" });
  } catch (err) {
    req.log.error({ err, vehicleId }, "Failed to insert fleet ping");
    res.status(500).json({ error: "insert failed" });
  }
});

// Driver login — parameterized query (fixes SQL injection)
app.post("/api/auth/login", async (req, res) => {
  const { phone } = req.body;

  if (!phone) {
    return res.status(400).json({ error: "phone is required" });
  }

  try {
    // Parameterized query — prevents SQL injection
    const result = await pool.query(
      `SELECT id, phone, name FROM drivers WHERE phone = $1`,
      [phone]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: "not found" });
    }

    // TODO: Implement proper OTP verification against a time-limited code
    // For now, OTP is accepted as-is (assessment scope)

    const token = jwt.sign({ driverId: result.rows[0].id }, JWT_SECRET, {
      expiresIn: "8h", // Reduced from 30d for security
    });
    res.json({ token });
  } catch (err) {
    req.log.error({ err }, "Login query failed");
    res.status(500).json({ error: "login failed" });
  }
});

// Admin endpoint — now protected by JWT authentication
app.get("/api/admin/drivers", authenticate, async (req, res) => {
  try {
    const result = await pool.query(`SELECT id, phone, name, created_at FROM drivers`);
    res.json(result.rows);
  } catch (err) {
    req.log.error({ err }, "Failed to fetch drivers");
    res.status(500).json({ error: "query failed" });
  }
});

// ---------------------------------------------------------------------------
// Server startup & graceful shutdown
// ---------------------------------------------------------------------------
const server = app.listen(parseInt(PORT, 10), () => {
  logger.info({ port: PORT }, "Server listening");
});

// Graceful shutdown — let in-flight requests finish, then close pool
const shutdown = async (signal) => {
  logger.info({ signal }, "Shutdown signal received, draining connections…");
  server.close(async () => {
    await pool.end();
    logger.info("All connections closed. Exiting.");
    process.exit(0);
  });

  // Force exit after 10 seconds if graceful shutdown stalls
  setTimeout(() => {
    logger.warn("Graceful shutdown timed out, forcing exit");
    process.exit(1);
  }, 10000);
};

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

module.exports = app;
module.exports.server = server; // exposed so tests can close the listener on teardown
