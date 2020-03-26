#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose-cloud-to-cloud.yml"
${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose-connect-onprem-to-cloud.yml"
${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose-executable-onprem-to-cloud.yml"