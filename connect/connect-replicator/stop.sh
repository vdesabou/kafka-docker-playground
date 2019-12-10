#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/stop.sh "${PWD}/docker-compose.plaintext.yml"
${DIR}/../../environment/sasl-ssl/stop.sh "${PWD}/docker-compose.sasl-ssl.yml"
${DIR}/../../environment/2way-ssl/stop.sh "${PWD}/docker-compose.2way-ssl.yml"