#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

docker-compose -f ../plaintext/docker-compose.yml -f ${DIR}/docker-compose.plaintext-microsoft.yml down -v
