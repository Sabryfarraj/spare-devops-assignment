function requireEnv(name, fallback) {
  const value = process.env[name] ?? fallback;
  if (value === undefined || value === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

module.exports = {
  port: Number(process.env.PORT ?? 8080),
  db: {
    host: requireEnv("DB_HOST", "localhost"),
    port: Number(requireEnv("DB_PORT", "5432")),
    database: requireEnv("DB_NAME", "notifications"),
    user: requireEnv("DB_USER", "app"),
    password: requireEnv("DB_PASSWORD", "app"),
  },
};
