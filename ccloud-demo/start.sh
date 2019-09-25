#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
SR_TYPE=${1:-SCHEMA_REGISTRY_DOCKER} 
CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     echo "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi


echo "The following ccloud config is used:"
echo "---------------"
cat ${CONFIG_FILE}
echo "---------------"


if [ "${SR_TYPE}" == "SCHEMA_REGISTRY_DOCKER" ]
then
     echo "INFO: Using Docker Schema Registry"
     ./ccloud-generate-env-vars.sh schema_registry_docker.config
else 
     echo "INFO: Using Confluent Cloud Schema Registry"
     ./ccloud-generate-env-vars.sh ${CONFIG_FILE}
fi

if [ -f ./delta_configs/env.delta ]
then
     source ./delta_configs/env.delta
else
     echo "ERROR: delta_configs/env.delta has not been generated"
     exit 1
fi

set +e
echo "Create topic customer-avro in Confluent Cloud"
kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" ${CONFIG_FILE} | tail -1` --command-config ${CONFIG_FILE} --topic customer-avro --create --replication-factor 3 --partitions 6
set -e

${DIR}/reset-cluster.sh



