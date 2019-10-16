#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/stop.sh "${PWD}/docker-compose.plaintext.yml"
${DIR}/../sasl-ssl/stop.sh "${PWD}/docker-compose.sasl-ssl.yml"
${DIR}/../kerberos/stop.sh "${PWD}/docker-compose.kerberos.yml"