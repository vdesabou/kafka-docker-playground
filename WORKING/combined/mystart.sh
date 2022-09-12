#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


# Create the CDC connector and add an element
./addcdc.sh
# Create the JDBC source connector and add an element
./addjdbc-src.sh
# Create the JDBC Sink and populate the topic
./addjdbc-sink.sh

sleep 5

./showtables.sh


