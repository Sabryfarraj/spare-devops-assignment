# syntax=docker/dockerfile:1

# Pinned by exact version AND digest (immutable). Bump via Renovate/Dependabot PR + CI smoke test.
ARG NODE_IMAGE=node:24.20.0-alpine@sha256:e67514e5d0f6c46656005e1b693b2ec9d52e80b641307de684d4a015ba7a4eaf

# ---- Stage 1: production dependencies only ----
FROM ${NODE_IMAGE} AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev --ignore-scripts

# ---- Stage 2: runtime image ----
FROM ${NODE_IMAGE} AS runtime

RUN apk add --no-cache tini

ENV NODE_ENV=production \
    PORT=8080

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Numeric non-root UID:GID (the "node" user) so runtimes can verify it.
USER 1000:1000
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "src/index.js"]