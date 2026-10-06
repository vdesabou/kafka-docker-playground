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
# doctor calls playground recursively, which must be on the PATH (the Build and Test
# step does the same)
export PATH="$PATH:${DIR}/cli"
# only the function library, for log: sourcing scripts/utils.sh also picks the CP
# version and rebuilds the connect image, on the docker engine that is about to stop
source ${DIR}/cli/src/lib/utils_function.sh

# not the default /run/podman/podman.sock: podman's tmpfiles.d creates /run/podman
# as 0700 root, so the runner could never reach a socket in there, whatever its mode.
# systemd creates this directory itself, with DirectoryMode below
podman_socket="/run/podman-api/podman.sock"

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
# the empty ListenStream= drops the default one before adding ours
sudo tee /etc/systemd/system/podman.socket.d/99-playground.conf > /dev/null << EOF
[Socket]
ListenStream=
ListenStream=${podman_socket}
SocketMode=0660
SocketUser=$(id -un)
SocketGroup=$(id -gn)
DirectoryMode=0755
EOF
sudo systemctl daemon-reload
# a service already activated by the previous socket keeps its old file descriptor
sudo systemctl stop podman.service || true
sudo systemctl enable podman.socket
sudo systemctl restart podman.socket

# containers that mount /var/run/docker.sock (the k3d registry cache of environment/cfk,
# the datadog agent) must reach podman, not the docker daemon stopped above: same
# link as the podman-docker package and podman machine set up
sudo ln -sf "${podman_socket}" /var/run/docker.sock

export DOCKER_HOST="unix://${podman_socket}"
if [ -n "$GITHUB_ENV" ]
then
    echo "DOCKER_HOST=${DOCKER_HOST}" >> "$GITHUB_ENV"
fi

if ! docker version > /dev/null 2>&1
then
    logerror "❌ the docker CLI cannot reach podman on ${DOCKER_HOST}"
    docker version 2>&1 | tail -5 || true
    ls -ld "$(dirname "${podman_socket}")" "${podman_socket}" || true
    sudo systemctl --no-pager status podman.socket podman.service || true
    sudo journalctl --no-pager -u podman.socket -u podman.service | tail -30 || true
    exit 1
fi

# fail the job here rather than in the middle of the first example
${DIR}/cli/playground doctor
