# Build stage
FROM node:20-slim AS builder

WORKDIR /app

# Install build dependencies for native modules (canvas, sharp)
RUN apt-get update && apt-get install -y \
    python3 \
    build-essential \
    pkg-config \
    libcairo2-dev \
    libpango1.0-dev \
    libjpeg-dev \
    libgif-dev \
    librsvg2-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package*.json ./

# Install all dependencies (needed for build)
RUN npm ci

# Copy source code
COPY src ./src
COPY tsconfig.json ./

# Build TypeScript
RUN npm run build

# Remove dev dependencies after build
RUN npm prune --omit=dev

# Runtime stage
FROM node:20-slim

WORKDIR /app

# Install runtime dependencies for canvas and sharp
RUN apt-get update && apt-get install -y \
    libcairo2 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libjpeg62-turbo \
    libgif7 \
    librsvg2-2 \
    && rm -rf /var/lib/apt/lists/*

# Copy dependencies from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy built application
COPY --from=builder /app/lib ./lib

# Copy package files
COPY package*.json ./

# Set ownership to node user (already exists in node base image)
RUN chown -R node:node /app

USER node

# Set environment variables
ENV NODE_ENV=production
ENV PORT=8080

# Expose port (Cloud Run specific)
EXPOSE 8080

# Health check (for local Docker, not used by Cloud Run)
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://localhost:8080/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})" || exit 1

# Start application
# Note: Cloud Run handles signals properly, so dumb-init is not needed
CMD ["node", "lib/index.js"]
