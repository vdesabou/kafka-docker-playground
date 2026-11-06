#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../ccloud/environment/stop.sh "${DIR}/docker-compose.mqtt-source.yml"
${DIR}/../../ccloud/environment/stop.sh "${DIR}/docker-compose.redshift.yml"
${DIR}/../../ccloud/environment/stop.sh "${DIR}/docker-compose.servicenow-source.yml"
${DIR}/../../ccloud/environment/stop.sh "${DIR}/docker-compose-connect-onprem-to-cloud.yml"