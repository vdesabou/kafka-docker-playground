#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/sasl-ssl/stop.sh "${PWD}/docker-compose.sasl-plain.yml"