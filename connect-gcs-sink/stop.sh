#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/stop.sh "${PWD}/docker-compose.plaintext.yml"
${DIR}/../sasl-ssl/stop.sh "${PWD}/docker-compose.sasl-ssl.yml"
${DIR}/../kerberos/stop.sh "${PWD}/docker-compose.kerberos.yml"
${DIR}/../ldap_authorizer_sasl_plain/stop.sh "${PWD}/docker-compose.ldap-authorizer-sasl-plain.yml"