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

if [ "${provider}" = "minikube" ]
then
    #######
    # minikube
    #######
    verify_installed "minikube"
    set +e
    log "Stop minikube if required"
    minikube delete
    set -e
    log "Start minikube"
    minikube start --cpus=8 --disk-size='50gb' --memory=16384
    log "Launch minikube dashboard in background"
    minikube dashboard &
elif [ "${provider}" = "aws" ]
then
    #######
    # aws
    #######
else
    logerror "Provider ${provider} is not supported"
    exit 1
fi

