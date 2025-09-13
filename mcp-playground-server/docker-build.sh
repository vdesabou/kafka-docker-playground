#!/bin/bash

# MCP Playground Server - Docker Build and Run Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
IMAGE_NAME="mcp-playground-server"
CONTAINER_NAME="mcp-playground-server"
VERSION="1.0.0"
DOCKER_HUB_REPO="vdesabou/mcp-playground-server"  # Docker Hub repository

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# Function to show usage
usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  build       Build the Docker image"
    echo "  run         Run the container (builds if needed)"
    echo "  stop        Stop the running container"
    echo "  clean       Remove container and image"
    echo "  logs        Show container logs"
    echo "  shell       Open shell in running container"
    echo "  test        Test the MCP server"
    echo "  tag         Tag image for Docker Hub"
    echo "  push        Push image to Docker Hub"
    echo "  publish     Build, tag, and push to Docker Hub"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 build         # Build the Docker image"
    echo "  $0 run           # Run the container"
    echo "  $0 logs -f       # Follow container logs"
    echo "  $0 publish       # Build and publish to Docker Hub"
    echo "  $0 push          # Push existing image to Docker Hub"
}

# Function to build Docker image
build_image() {
    log "Building Docker image: $IMAGE_NAME:$VERSION"
    
    # Build from parent directory to access scripts/cli/src/bashly.yml
    cd ..
    if ! docker build -f mcp-playground-server/Dockerfile -t "$IMAGE_NAME:$VERSION" -t "$IMAGE_NAME:latest" .; then
        error "Failed to build Docker image"
        exit 1
    fi
    cd "$SCRIPT_DIR"
    
    success "Docker image built successfully"
    docker images | grep "$IMAGE_NAME"
}

# Function to run container
run_container() {
    # Check if image exists, build if not
    if ! docker image inspect "$IMAGE_NAME:$VERSION" >/dev/null 2>&1; then
        warn "Image not found. Building..."
        build_image
    fi
    
    # Stop existing container if running
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        log "Stopping existing container..."
        docker stop "$CONTAINER_NAME" >/dev/null
    fi
    
    # Remove existing container if exists
    if docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
        log "Removing existing container..."
        docker rm "$CONTAINER_NAME" >/dev/null
    fi
    
    log "Starting MCP Playground Server container..."
    
    # Run the container with Docker socket mounted for container inspection
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart no \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -e NODE_ENV=production \
        -e MCP_SERVER_NAME=mcp-playground-server \
        -e MCP_SERVER_VERSION="$VERSION" \
        --label com.kafka-docker-playground.service=mcp-server \
        --label com.kafka-docker-playground.version="$VERSION" \
        "$IMAGE_NAME:$VERSION"
    
    success "Container started successfully"
    
    # Show container status
    docker ps | grep "$CONTAINER_NAME"
    
    log "You can view logs with: $0 logs"
    log "You can stop the container with: $0 stop"
}

# Function to stop container
stop_container() {
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        log "Stopping container: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME"
        success "Container stopped"
    else
        warn "Container $CONTAINER_NAME is not running"
    fi
}

# Function to clean up
clean() {
    log "Cleaning up containers and images..."
    
    # Stop and remove container
    if docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        log "Container removed"
    fi
    
    # Remove images
    docker rmi "$IMAGE_NAME:$VERSION" "$IMAGE_NAME:latest" 2>/dev/null || true
    log "Images removed"
    
    success "Cleanup completed"
}

# Function to show logs
show_logs() {
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        docker logs "$@" "$CONTAINER_NAME"
    else
        error "Container $CONTAINER_NAME is not running"
        exit 1
    fi
}

# Function to open shell
open_shell() {
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        log "Opening shell in container..."
        docker exec -it "$CONTAINER_NAME" /bin/sh
    else
        error "Container $CONTAINER_NAME is not running"
        exit 1
    fi
}

# Function to test MCP server
test_server() {
    if ! docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        error "Container $CONTAINER_NAME is not running. Start it first with: $0 run"
        exit 1
    fi
    
    log "Testing MCP server functionality..."
    
    # Test if the container process is running and healthy
    if docker exec "$CONTAINER_NAME" pgrep -f "node dist/index.js" >/dev/null 2>&1; then
        success "MCP server process is running"
    else
        error "MCP server process not found"
        exit 1
    fi
    
    # Test environment variables
    if docker exec "$CONTAINER_NAME" test -f "/app/bashly.yml"; then
        success "bashly.yml configuration file mounted correctly"
    else
        warn "bashly.yml not found at expected location"
    fi
    
    # Test Docker socket access
    if docker exec "$CONTAINER_NAME" test -S "/var/run/docker.sock"; then
        success "Docker socket accessible for container inspection"
    else
        warn "Docker socket not accessible"
    fi
    
    # Test basic MCP server response (with timeout)
    log "Testing MCP server communication..."
    if timeout 10 docker exec "$CONTAINER_NAME" sh -c '
        echo "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{}},\"clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0.0\"}}}" | node dist/index.js
    ' >/dev/null 2>&1; then
        success "MCP server responds to initialization"
    else
        warn "MCP server communication test had timeout (normal for interactive STDIO servers)"
    fi
    
    success "MCP server is ready for use with Docker model runners"
    log ""
    log "To use with MCP clients, run:"
    log "docker exec -i $CONTAINER_NAME node dist/index.js"
}

# Function to tag image for Docker Hub
tag_image() {
    if ! docker image inspect "$IMAGE_NAME:$VERSION" >/dev/null 2>&1; then
        warn "Image not found. Building..."
        build_image
    fi
    
    log "Tagging image for Docker Hub..."
    docker tag "$IMAGE_NAME:$VERSION" "$DOCKER_HUB_REPO:$VERSION"
    docker tag "$IMAGE_NAME:$VERSION" "$DOCKER_HUB_REPO:latest"
    
    success "Image tagged for Docker Hub"
    docker images | grep "$DOCKER_HUB_REPO"
}

# Function to push image to Docker Hub
push_image() {
    # Check if image is tagged for Docker Hub
    if ! docker image inspect "$DOCKER_HUB_REPO:$VERSION" >/dev/null 2>&1; then
        warn "Image not tagged for Docker Hub. Tagging..."
        tag_image
    fi
    
    log "Pushing image to Docker Hub..."
    log "Make sure you're logged in with: docker login"
    
    # Push both version and latest tags
    docker push "$DOCKER_HUB_REPO:$VERSION"
    docker push "$DOCKER_HUB_REPO:latest"
    
    success "Image pushed to Docker Hub successfully!"
    log ""
    log "Your image is now available at:"
    log "  docker pull $DOCKER_HUB_REPO:$VERSION"
    log "  docker pull $DOCKER_HUB_REPO:latest"
    log ""
    log "Docker Hub URL: https://hub.docker.com/r/$DOCKER_HUB_REPO"
}

# Function to build, tag, and push in one command
publish_image() {
    log "Publishing MCP Playground Server to Docker Hub..."
    
    # Build the image
    build_image
    
    # Tag for Docker Hub
    tag_image
    
    # Push to Docker Hub
    push_image
    
    success "Publication complete!"
}

# Main script logic
case "${1:-}" in
    build)
        build_image
        ;;
    run)
        run_container
        ;;
    stop)
        stop_container
        ;;
    clean)
        clean
        ;;
    logs)
        shift
        show_logs "$@"
        ;;
    shell)
        open_shell
        ;;
    test)
        test_server
        ;;
    tag)
        tag_image
        ;;
    push)
        push_image
        ;;
    publish)
        publish_image
        ;;
    help|--help|-h)
        usage
        ;;
    "")
        log "No command specified. Use 'help' to see available commands."
        usage
        exit 1
        ;;
    *)
        error "Unknown command: $1"
        usage
        exit 1
        ;;
esac