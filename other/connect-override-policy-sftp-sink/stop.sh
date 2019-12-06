#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/sasl-plain/stop.sh "${PWD}/docker-compose.sasl-plain.yml"