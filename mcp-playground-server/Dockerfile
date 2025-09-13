# Multi-stage build for optimized Docker image
# Stage 1: Build stage
FROM node:20-alpine3.20 AS builder

WORKDIR /app

# Copy package files
COPY mcp-playground-server/package*.json ./
COPY mcp-playground-server/tsconfig.json ./

# Install all dependencies (including dev dependencies for building)
RUN npm ci

# Copy source code
COPY mcp-playground-server/src/ ./src/

# Build the TypeScript project
RUN npm run build

# Stage 2: Production stage  
FROM node:20-alpine3.20 AS production

WORKDIR /app

# Copy package files
COPY mcp-playground-server/package*.json ./

# Install only production dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy built application from builder stage
COPY --from=builder /app/dist ./dist

# Copy any additional files needed at runtime
COPY --from=builder /app/src ./src

# Copy bashly.yml configuration file from scripts directory
COPY scripts/cli/src/bashly.yml ./bashly.yml

# Copy entrypoint script
COPY mcp-playground-server/entrypoint.sh ./entrypoint.sh

# Build the TypeScript project, create user, and set permissions
RUN addgroup -g 1001 -S nodejs && \
    adduser -S mcp -u 1001 && \
    chmod +x ./entrypoint.sh && \
    chown -R mcp:nodejs /app

USER mcp

# Expose port (for potential future HTTP transport)
EXPOSE 3000

# Set environment variables
ENV NODE_ENV=production
ENV MCP_SERVER_NAME=mcp-playground-server
ENV MCP_SERVER_VERSION=1.0.0

# Set entrypoint
ENTRYPOINT ["./entrypoint.sh"]

# Default command - run the MCP server
CMD ["npm", "start"]