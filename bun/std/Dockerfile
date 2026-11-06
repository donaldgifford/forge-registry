# Multi-stage Dockerfile for ShitWiz UI
# Supports both development (hot reload) and production (optimized static build with Caddy)

# =============================================================================
# Base stage: Node.js + Bun
# =============================================================================
FROM node:20-alpine@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293 AS base

# Install Bun globally
RUN npm install -g bun

# Set working directory for all subsequent stages
WORKDIR /app

# =============================================================================
# Development stage: Hot reload for local development
# =============================================================================
FROM base AS dev

# Copy dependency files (lockfile is optional)
COPY package.json ./
COPY bun.lock* ./

# Install all dependencies (including devDependencies)
RUN bun install

# Copy application code
COPY . .

# Expose Vite dev server port
EXPOSE 3000

# Start Vite dev server with host binding for Docker
CMD ["bun", "run", "dev", "--host"]

# =============================================================================
# Builder stage: Production build
# =============================================================================
FROM base AS builder

# Copy dependency files (lockfile is optional)
COPY package.json ./
COPY bun.lock* ./

# Install dependencies
RUN bun install

# Copy application code
COPY . .

# Build optimized production bundle
RUN bun run build

# =============================================================================
# Production stage: Caddy static file server
# =============================================================================
FROM caddy:2-alpine@sha256:78bd35025c7ba85961dd149ae670315129954e77abe2383ac47c89106b35ade9 AS production

# Copy built static files from builder stage
COPY --from=builder /app/dist /srv

# Copy Caddy configuration
COPY Caddyfile /etc/caddy/Caddyfile

# Copy entrypoint script for runtime config injection
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Expose HTTP port
EXPOSE 80

# Use entrypoint for runtime config, then start Caddy
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
