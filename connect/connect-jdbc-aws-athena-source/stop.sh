#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CLUSTER_NAME=pg${USER}jdbcredshift${GITHUB_RUN_NUMBER}${TAG}
CLUSTER_NAME=${CLUSTER_NAME//[-._]/}

set +e
log "Delete AWS Redshift cluster"
aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot
log "Delete security group sg$CLUSTER_NAME"
aws ec2 delete-security-group --group-name sg$CLUSTER_NAME

stop_all "$DIR"