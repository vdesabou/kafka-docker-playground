#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

export ANSIBLE_ARCHIVE_CACHE_DIR="${ANSIBLE_ARCHIVE_CACHE_DIR:-$HOME/.playground-ansible-cache}"
export ANSIBLE_DOCKER_SOCKET="${ANSIBLE_DOCKER_SOCKET:-/var/run/docker.sock}"
docker compose -f ${DIR}/../../environment/ansible/docker-compose.yml --profile '*' down -v --remove-orphans
