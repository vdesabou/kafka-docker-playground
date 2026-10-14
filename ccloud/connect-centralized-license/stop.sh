#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose.mqtt-source.yml"
${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose.redshift.yml"
${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose.servicenow-source.yml"
${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose-connect-onprem-to-cloud.yml"