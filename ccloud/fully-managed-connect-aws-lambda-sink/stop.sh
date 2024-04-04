#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

LAMBDA_ROLE_NAME=playground_lambda_role$TAG
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME//[-.]/}

LAMBDA_FUNCTION_NAME=playground_lambda_function$TAG
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME//[-.]/}

set +e
log "Cleanup, this might fail..."
aws iam delete-role --role-name $LAMBDA_ROLE_NAME
aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME
set +e

maybe_delete_ccloud_environment