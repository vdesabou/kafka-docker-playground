#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# loading env variables
source ${DIR}/../../scripts/utils.sh

if [ -z "$FLINK_JAR_PATH" ]
then
    # Flink variable isn't set
    log "❌ FLINK_JAR_PATH is not set, you need to export the variable with a path to the jar file(ex: export FLINK_JAR_PATH=/path/to/my/file.jar)"
    exit
fi

source ${DIR}/../../scripts/flink_download_connectors.sh

docker-compose up -d