#!/bin/bash
# Switch a GitHub Actions ubuntu runner from Docker to rootful Podman.
#
# Called from .github/workflows/ci.yml when the workflow is started with
# container_engine=podman. The playground keeps using the docker CLI and the docker
# compose plugin the runner already has: they are pointed at the podman socket with
# DOCKER_HOST, exported to the following steps through $GITHUB_ENV. From there:
#   - utils_function.sh turns DOCKER_BUILDKIT off on its own (DOCKER_HOST mentions podman)
#   - run-tests.sh stores the results with a -podman suffix, apart from the docker ones
#
# Rootful, like the recommended macOS setup: rootless would map the files containers
# write into bind mounts (certificates, keystores, ...) to subuids the runner cannot read.
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/utils.sh

podman_socket="/run/podman/podman.sock"

log "🦭 Installing podman, netavark and aardvark-dns"
# netavark + aardvark-dns: compose services resolve each other by name (broker,
# connect, ...), which the legacy cni backend cannot do without extra plugins
sudo apt-get update -qq
sudo apt-get install -y -qq podman netavark aardvark-dns > /dev/null
podman --version

log "⚙️ Configuring podman"
sudo mkdir -p /etc/containers/containers.conf.d /etc/containers/registries.conf.d
sudo tee /etc/containers/containers.conf.d/99-playground.conf > /dev/null << EOF
[network]
network_backend = "netavark"
EOF
# the docker compat API resolves short names (postgres:14) to docker.io on recent
# versions; make native podman and older versions do the same
sudo tee /etc/containers/registries.conf.d/99-playground.conf > /dev/null << EOF
unqualified-search-registries = ["docker.io"]
short-name-mode = "permissive"
EOF

log "🛑 Stopping docker, so that nothing silently falls back to it"
sudo systemctl stop docker.socket docker.service containerd.service || true

log "🔌 Starting the rootful podman socket, readable by $(id -un)"
sudo mkdir -p /etc/systemd/system/podman.socket.d
sudo tee /etc/systemd/system/podman.socket.d/99-playground.conf > /dev/null << EOF
[Socket]
SocketMode=0660
SocketGroup=$(id -gn)
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now podman.socket
sudo systemctl restart podman.socket

export DOCKER_HOST="unix://${podman_socket}"
if [ -n "$GITHUB_ENV" ]
then
    echo "DOCKER_HOST=${DOCKER_HOST}" >> "$GITHUB_ENV"
fi

# fail the job here rather than in the middle of the first example
${DIR}/cli/playground doctor
