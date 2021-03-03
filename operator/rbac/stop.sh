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

if [ "${provider}" = "minikube" ]
then
    minikube delete
elif [ "${provider}" = "aws" ]
then
    #######
    # aws
    #######
    log "Deleting EKS cluster"
    eksctl delete cluster --name ${eks_cluster_name}
else
    logerror "Provider ${provider} is not supported"
    exit 1
fi