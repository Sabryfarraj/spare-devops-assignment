# DevOps Assignment — Starter API

This is the **starter repository** for the Spare Junior DevOps take-home assignment.

Your task is **not** to rewrite this application. Instead, containerize it, run it locally with Docker Compose, add CI/CD, and write operational scripts. See the full assignment brief for details.

## What's included

A minimal Node.js + Express API backed by PostgreSQL:

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check (includes DB connectivity) |
| GET | `/users` | List all users |
| POST | `/users` | Create a user (`{ "name": "Alice" }`) |
| GET | `/notifications?user_id=<id>` | List notifications for a user |
| POST | `/notifications` | Create a notification |

## Prerequisites

- Node.js 18+
- PostgreSQL running locally (for native development only)

## Run locally (without Docker)

Candidates are expected to **Dockerize** this app as part of the assignment. These steps are for verifying the starter code before you begin:

```bash
cp .env.example .env
npm install
npm start
```

Example requests:

```bash
curl http://localhost:8080/health
curl -X POST http://localhost:8080/users -H "Content-Type: application/json" -d '{"name":"Alice"}'
curl http://localhost:8080/users
curl -X POST http://localhost:8080/notifications \
  -H "Content-Type: application/json" \
  -d '{"user_id":1,"title":"Hello","body":"Welcome!","channel":"in_app"}'
curl "http://localhost:8080/notifications?user_id=1"
```

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP port | `8080` |
| `DB_HOST` | PostgreSQL host | `localhost` |
| `DB_PORT` | PostgreSQL port | `5432` |
| `DB_NAME` | Database name | `notifications` |
| `DB_USER` | Database user | `app` |
| `DB_PASSWORD` | Database password | `app` |

## What you submit

Create **your own** GitHub repository, push your solution there (Dockerfile, Compose, CI, scripts), and share that link with us.
