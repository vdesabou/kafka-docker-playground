# MCP Playground Server - Docker Deployment

This directory contains Docker configuration for the MCP (Model Context Protocol) Playground Server, allowing it to be used with docker model runners and containerized environments.

## 🐳 Quick Start

### Prerequisites

1. Docker installed on your system

### Build and Run

```bash
# Build the Docker image
./docker-build.sh build

# Run the container
./docker-build.sh run

# View logs
./docker-build.sh logs -f

# Stop the container
./docker-build.sh stop
```

## Building the Docker Image

From the mcp-playground-server directory:

```bash
./docker-build.sh build
```

The `bashly.yml` configuration file is embedded directly in the Docker image from the original `scripts/cli/src/bashly.yml` location, so no external file mounting is required.

### Using Docker Compose

```bash
# Start the service
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the service
docker-compose down
```

## 📁 Docker Files

- **`Dockerfile`** - Multi-stage build configuration
- **`docker-compose.yml`** - Orchestration configuration
- **`entrypoint.sh`** - Container startup script
- **`docker-build.sh`** - Build and management script
- **`.dockerignore`** - Build optimization

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_ENV` | `production` | Node.js environment |
| `MCP_SERVER_NAME` | `mcp-playground-server` | Server identification |
| `MCP_SERVER_VERSION` | `1.0.0` | Server version |
| `BASHLY_YML_PATH` | `/app/bashly.yml` | Path to CLI configuration |

### Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `/var/run/docker.sock` | `/var/run/docker.sock` | Docker API access (read-only) |

**Note**: The bashly.yml configuration is now embedded directly in the Docker image, eliminating the need for external volume mounts.

## 🚀 Integration with Model Runners

### Claude Desktop (with Docker)

Update your MCP configuration file (usually `~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):

```json
{
  "mcpServers": {
    "playground": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
        "mcp-playground-server:1.0.0",
        "node", "dist/index.js"
      ]
    }
  }
}
```

### VS Code with Docker

Update `.vscode/mcp.json` in your workspace:

```json
{
  "mcpServers": {
    "playground": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
        "mcp-playground-server:1.0.0",
        "node", "dist/index.js"
      ]
    }
  }
}
```

**✅ That's it!** No need to mount bashly.yml files - everything is embedded in the Docker image.

## 🛠 Management Commands

```bash
# Build the image
./docker-build.sh build

# Run the container
./docker-build.sh run

# Stop the container
./docker-build.sh stop

# View logs (follow)
./docker-build.sh logs -f

# Open shell in container
./docker-build.sh shell

# Test server functionality
./docker-build.sh test

# Clean up (remove container and images)
./docker-build.sh clean

# Show help
./docker-build.sh help
```

## 🔍 Container Features

### Docker Integration
- Docker CLI included for container inspection
- Docker socket mounted for real-time container data
- Network access to other containers

### Security
- Non-root user execution
- Minimal Alpine Linux base
- Read-only mounts where possible
- Health checks included

### Monitoring
- Built-in health checks
- Structured logging
- Resource-optimized multi-stage build

## 🐛 Troubleshooting

### Container Won't Start
```bash
# Check logs
./docker-build.sh logs

# Check container status
docker ps -a | grep mcp-playground

# Verify Docker socket
ls -la /var/run/docker.sock
```

### MCP Server Not Responding
```bash
# Test server functionality
./docker-build.sh test

# Open shell and debug
./docker-build.sh shell

# Check health status
docker inspect mcp-playground-server
```

### Permission Issues
```bash
# Check Docker socket permissions
sudo chmod 666 /var/run/docker.sock

# Or add user to docker group
sudo usermod -aG docker $USER
```

## 📊 Performance Considerations

- **Image Size**: ~100MB (optimized multi-stage build)
- **Memory Usage**: ~50MB baseline
- **CPU Usage**: Minimal when idle
- **Startup Time**: ~5-10 seconds

## 🔄 Updates

```bash
# Update and rebuild
git pull
./docker-build.sh clean
./docker-build.sh build
./docker-build.sh run
```

## 🧪 Development

For development with hot reload:

```bash
# Use docker-compose with dev profile
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# Or run with volume mounts
docker run -it \
  -v $(pwd)/src:/app/src \
  -v $(pwd)/dist:/app/dist \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  mcp-playground-server:latest \
  npm run dev
```

## 📝 Notes

- The container runs as a non-root user for security
- Docker socket access is required for container inspection features
- The server uses STDIO transport by default (suitable for MCP clients)
- Health checks ensure container reliability
- Logs are structured for easy parsing and monitoring

For more information about the MCP server itself, see the main [README.md](README.md).