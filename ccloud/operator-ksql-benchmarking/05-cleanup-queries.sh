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

# https://rmoff.net/2019/03/25/terminate-all-ksql-queries/
log "TERMINATE all queries, if applicable"
kubectl exec -i connectors-0 -- bash -c "curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
         -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
         -d '{\"ksql\": \"SHOW QUERIES;\"}' | \
  jq '.[].queries[].id' | \
  xargs -Ifoo curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
           -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
           -d '{\"ksql\": \"TERMINATE 'foo';\"}' | jq ."
log "DROP all streams, if applicable"
kubectl exec -i connectors-0 -- bash -c "curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
           -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
           -d '{\"ksql\": \"SHOW STREAMS;\"}' | \
    jq '.[].streams[].name' | \
    xargs -Ifoo curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
             -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
             -d '{\"ksql\": \"DROP STREAM 'foo';\"}' | jq ."
log "DROP all tables, if applicable"
kubectl exec -i connectors-0 -- bash -c "curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
             -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
             -d '{\"ksql\": \"SHOW TABLES;\"}' | \
      jq '.[].tables[].name' | \
      xargs -Ifoo curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
               -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
               -d '{\"ksql\": \"DROP TABLE 'foo';\"}' | jq ."