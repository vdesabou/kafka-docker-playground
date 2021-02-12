#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# read configuration files
#
if [ -r ${DIR}/test.properties ]
then
    . ${DIR}/test.properties
else
    logerror "Cannot read configuration file ${DIR}/test.properties"
    exit 1
fi

if [ -r ${DIR}/ccloud-cluster.properties ]
then
    . ${DIR}/ccloud-cluster.properties
else
    logerror "Cannot read configuration file ${APP_HOME}/ccloud-cluster.properties"
    exit 1
fi

verify_installed "kubectl"
verify_installed "helm"

log "START BENCHMARK"
kubectl exec -i ksql-0 -- bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/localhost:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://localhost:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

INSERT INTO ORDERS SELECT * FROM ORDERS_ORIGINAL;
INSERT INTO SHIPMENTS SELECT * FROM SHIPMENTS_ORIGINAL;
EOF
