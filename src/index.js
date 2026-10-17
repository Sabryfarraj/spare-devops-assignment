const express = require("express");
const config = require("./config");
const { pool, initDb } = require("./db");

const app = express();
app.use(express.json());

app.get("/health", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok" });
  } catch (err) {
    res.status(503).json({ status: "error", message: "database unavailable" });
  }
});

app.get("/users", async (_req, res) => {
  const result = await pool.query(
    "SELECT id, name, created_at FROM users ORDER BY id"
  );
  res.json(result.rows);
});

app.post("/users", async (req, res) => {
  const { name } = req.body ?? {};
  if (!name || typeof name !== "string") {
    return res.status(400).json({ error: "name is required" });
  }

  const result = await pool.query(
    "INSERT INTO users (name) VALUES ($1) RETURNING id, name, created_at",
    [name.trim()]
  );
  res.status(201).json(result.rows[0]);
});

app.get("/notifications", async (req, res) => {
  const userId = req.query.user_id;
  if (!userId) {
    return res.status(400).json({ error: "user_id query parameter is required" });
  }

  const result = await pool.query(
    `SELECT id, user_id, title, body, channel, read, created_at
     FROM notifications
     WHERE user_id = $1
     ORDER BY id`,
    [userId]
  );
  res.json(result.rows);
});

app.post("/notifications", async (req, res) => {
  const { user_id, title, body, channel = "in_app" } = req.body ?? {};

  if (!user_id || !title || !body) {
    return res.status(400).json({
      error: "user_id, title, and body are required",
    });
  }

  const result = await pool.query(
    `INSERT INTO notifications (user_id, title, body, channel)
     VALUES ($1, $2, $3, $4)
     RETURNING id, user_id, title, body, channel, read, created_at`,
    [user_id, title, body, channel]
  );
  res.status(201).json(result.rows[0]);
});

async function start() {
  await initDb();
  app.listen(config.port, () => {
    console.log(`API listening on port ${config.port}`);
  });
}

start().catch((err) => {
  console.error("Failed to start:", err.message);
  process.exit(1);
});
