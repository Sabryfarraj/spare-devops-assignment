# Spare DevOps Assignment

Node.js 24 + Express API with PostgreSQL, containerized and released through GitHub Actions to GHCR, with two environments: **stg** and **prod**.

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Health check (includes DB) |
| GET / POST | `/users` | List / create users (`{"name":"Alice"}`) |
| GET | `/notifications?user_id=<id>` | List a user's notifications |
| POST | `/notifications` | Create a notification |

## Architecture

```
stg branch ──push──► Release (stg) ──► ghcr.io/sabryfarraj/spare-devops-assignment-stg   (public)
main branch ─manual─► Release (prod) ─approval─► ghcr.io/sabryfarraj/spare-devops-assignment (private)

docker-compose-<env>.yml:  api (127.0.0.1:8080) ──► db (Postgres 18, volume pgdata)
```

- **Dockerfile:** multi-stage, `node:24.20.0-alpine` pinned by digest, `tini` as PID 1, non-root `USER 1000:1000`, `HEALTHCHECK`.
- **Compose** (one standalone file per environment): healthchecks, private network, named volume, `read_only`, `cap_drop: ALL`, `no-new-privileges`. The API listens only on `127.0.0.1:8080`.
- **Postgres** is a GHCR mirror of `postgres:18-alpine` (18.6), amd64 only, pinned by digest: `postgres-stg` (public) and `postgres` (private).

## Run it

Requirements: Docker with Compose v2, plus `bash` and `curl` for the scripts (Linux, WSL or Git Bash).

Create `.env` in the project root (it is gitignored):

```
DB_NAME=notifications
DB_USER=app
DB_PASSWORD=<choose one>
```

**stg** (public images, no login):

```bash
cd scripts
./stg.sh up        # start and wait until healthy (safe to rerun)
./stg.sh status    # service health + /health, exit 1 if unhealthy
./stg.sh smoke     # create a user + notification, read them back
./stg.sh logs      # last API logs (TAIL=200, FOLLOW=1)
./stg.sh down      # stop, keep the database
```

**prod** (private images): log in once with a **classic** PAT that has `read:packages`, then use the same commands with `prod.sh`. The prod script checks the login before `up`, `status` and `smoke`.

```bash
docker login ghcr.io -u <github-user>
cd scripts
./prod.sh up
```

Only one stack can run at a time, because both use port 8080.

The brief says `docker compose up`. This repo has no default compose file, so the plain Compose equivalent is `docker compose -f docker-compose-stg.yml up -d` (or `-f docker-compose-prod.yml`).

## CI/CD

| Workflow | Trigger | Jobs |
|---|---|---|
| **Release (stg)** | PR into `main`/`stg`, push to `stg` | `verify` → `publish` → `cleanup` (PRs run `verify` only) |
| **Release (prod)** | Manual (`workflow_dispatch`), from `main` only | `guard` → `verify` → `publish` (waits for approval) → `cleanup` |

- **verify:** builds the image as `…-stg:ci`, starts `docker-compose-stg.yml` with it (`--pull never`), runs a smoke test and tears down. Nothing is pushed.
- **publish:** reserves the next version as a git tag, then builds and pushes to GHCR (login via `GITHUB_TOKEN`).
- **cleanup:** `snok/container-retention-policy`. Image versions younger than 1 day are kept; of the older ones, the newest 10 are kept per package.

**Branching:** work goes to `stg` (auto-released to stg). `main` is production and only changes through a PR from `stg`, merged with a merge commit. A prod release is started by hand from `main`.

**Tagging:** each package has its own counter.

| | Image tags | Git tag on the commit |
|---|---|---|
| stg | `vN`, `latest`, `sha-<7>` | `stg-vN` |
| prod | `vN`, `latest`, `sha-<7>` | `vN` |

The next N is computed from the existing git tags. The git tags need different prefixes because both environments share one repo.

**Secrets:** `DB_NAME`, `DB_USER` and `DB_PASSWORD` live in the GitHub **environments** `stg` and `prod` (none at repo level). `verify` uses `stg`. `prod` requires a reviewer.

**Branch rules:** `main` requires a PR and a passing `verify` check, with 0 approvals and merge commits only. `stg` cannot be deleted or force-pushed.

## Manual test

**1. Release flow** (PowerShell or bash, project root). An empty commit is enough:

```bash
git switch stg
git pull
git commit --allow-empty -m "chore: test release flow"
git push
gh run watch --exit-status                      # stg: verify, publish (-stg:vN), cleanup
gh pr create --base main --head stg --title "chore: test release flow" --body "Release flow test."
gh pr checks --watch                            # wait for "verify (pull_request)" ✓
gh pr merge --merge --delete-branch=false
gh workflow run "Release (prod)" --ref main
```

Approve the run in **Actions → Release (prod) → Review deployments → prod → Approve and deploy**, then:

```bash
gh run watch --exit-status                      # prod: guard, verify, publish (:vN), cleanup
```

**2. Scripts** (from `scripts/`):

```bash
./stg.sh up
./stg.sh status
./stg.sh smoke
./stg.sh logs
./prod.sh up                  # must fail: port 8080 used by stg
./stg.sh down

./prod.sh up
./prod.sh status
./prod.sh smoke

docker logout ghcr.io
./prod.sh status              # must fail with the login message
./prod.sh down                # warns, still stops the stack
docker login ghcr.io -u <github-user>
```

On Windows, run Git from PowerShell and the scripts from WSL or Git Bash. Git inside WSL on `/mnt/c` reports every file as changed, because of line endings.

## Decisions and trade-offs

- **Public stg images, private prod images:** anyone can run stg without credentials, while prod needs a `read:packages` token.
- **Postgres mirror:** amd64 only and pinned by digest, so it is reproducible and doesn't depend on Docker Hub limits. It won't run natively on arm64, and updates are a manual re-mirror.
- **Manual prod release with approval**, instead of auto-deploy on merge to `main`: releasing is a deliberate act with a human gate.
- **No required PR approvals:** this is a solo repo and GitHub doesn't allow approving your own PR. The human gate is the prod environment approval.
- **Two scripts (`stg.sh`, `prod.sh`)** instead of the brief's single `ops.sh <cmd> [env]`: clearer to use, and prod gets a login pre-check. The cost is shared code that must be kept in sync.
- **`tini` as PID 1:** forwards signals and reaps zombies. The app itself has no SIGTERM handler and no async error handling; changing app code is out of scope.
- **Version counters come from git tags,** not from the registry, so versions are visible in the repo and a duplicate tag fails the release early.
