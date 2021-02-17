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

verify_installed "ccloud"

export CCLOUD_EMAIL=$ccloud_login
export CCLOUD_PASSWORD=$ccloud_password

ccloud login

set +e
ccloud kafka cluster delete ksql-benchmarking
set -e
ccloud kafka cluster create ksql-benchmarking --type dedicated --cloud ${provider} --cku ${ckus} --environment ${environment_id} --region ${eks_region}
