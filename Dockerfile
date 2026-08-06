# ============================================================
# Multi-stage production Dockerfile for Fleet Ping Service
# ============================================================

# --- Stage 1: Install dependencies ---
FROM node:20-alpine AS deps

WORKDIR /app

# Copy only package manifests first for better layer caching
COPY package.json package-lock.json* ./

# Use npm ci for deterministic, reproducible installs
# --omit=dev excludes devDependencies from the production image
RUN npm ci --omit=dev && npm cache clean --force

# --- Stage 2: Production runtime ---
FROM node:20-alpine AS runtime

# Security: add curl for HEALTHCHECK
RUN apk add --no-cache curl

# Security: run as the built-in non-root 'node' user
USER node

ENV NODE_ENV=production

WORKDIR /app

# Copy production node_modules from deps stage
COPY --from=deps --chown=node:node /app/node_modules ./node_modules

# Copy application source
COPY --chown=node:node server.js package.json ./

# Only expose the application port (no SSH)
EXPOSE 3000

# Healthcheck for container orchestrators
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
