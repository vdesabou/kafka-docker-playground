#!/bin/bash
# cfk-rbac is the cfk deployment with RBAC: same start.sh, see environment/cfk-rbac/cfk-rbac.sh
# (sourced, not executed, so that $0 and the recorded test file stay this script)
DIR_CFK_RBAC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
export CFK_ENVIRONMENT="cfk-rbac"
source "${DIR_CFK_RBAC}/../cfk/start.sh" "$@"
