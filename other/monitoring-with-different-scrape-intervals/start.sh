#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f "${DIR}/jmx_prometheus_httpserver-0.16.1-jar-with-dependencies.jar" ]
then
    log "Downloading jmx_prometheus_httpserver-0.16.1-jar-with-dependencies.jar"
    wget https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_httpserver/0.16.1/jmx_prometheus_httpserver-0.16.1-jar-with-dependencies.jar
fi

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"