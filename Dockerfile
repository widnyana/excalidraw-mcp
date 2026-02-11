# Stage 1: Builder - Node.js with bun for build
FROM node:22-alpine AS builder

WORKDIR /app

# Install bun for build (required by build script)
RUN npm install -g bun

# Copy package files
COPY package.json package-lock.json ./

# Install all dependencies (including devDependencies for build)
RUN npm ci --cache=/tmp/npm-cache && \
    rm -rf /tmp/npm-cache

# Copy source files
COPY tsconfig.json tsconfig.server.json vite.config.ts ./
COPY src ./src
COPY scripts ./scripts

# Build application
RUN npm run build

# Stage 2: Runtime - minimal Node.js alpine
FROM node:22-alpine

# Docker Hub metadata labels
LABEL org.opencontainers.image.title="Excalidraw MCP Server"
LABEL org.opencontainers.image.description="Streamable Excalidraw diagram MCP App server"
LABEL org.opencontainers.image.version="0.3.2"
LABEL org.opencontainers.image.source="https://github.com/widnyana/excalidraw-mcp"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S mcp && \
  adduser -S -D -H -u 1001 -s /bin/sh -G mcp mcp

# Copy only production dependencies
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --cache=/tmp/empty-cache && \
  rm -rf /tmp/empty-cache /root/.npm

# Copy built artifacts from builder stage
COPY --from=builder --chown=mcp:mcp /app/dist ./dist

# Create checkpoint directory with proper permissions
RUN mkdir -p /tmp/excalidraw-mcp-checkpoints && \
  chown -R mcp:mcp /tmp/excalidraw-mcp-checkpoints

# Switch to non-root user
USER mcp

# Environment variables
ENV NODE_ENV=production
ENV PORT=3001

# Expose MCP HTTP endpoint port
EXPOSE 3001

# Health check - HTTP endpoint exists (200 OK or 405 Method Not Allowed is valid)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3001/mcp', (r) => {process.exit(r.statusCode === 200 || r.statusCode === 405 ? 0 : 1)})"

# Default command runs HTTP server on port 3001
CMD ["node", "dist/index.js"]
