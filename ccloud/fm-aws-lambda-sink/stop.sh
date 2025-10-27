#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

LAMBDA_ROLE_NAME=pg${USER}fmlambdabrole${GITHUB_RUN_NUMBER}${TAG_BASE}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME//[-._]/}

LAMBDA_FUNCTION_NAME=pg${USER}fmlambdafn${GITHUB_RUN_NUMBER}${TAG_BASE}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME//[-._]/}

set +e
log "Cleanup, this might fail..."
aws iam delete-role --role-name $LAMBDA_ROLE_NAME
aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME
set +e

maybe_delete_ccloud_environment