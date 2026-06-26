#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # running with github actions



    SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
    SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
    SALESFORCE_SECURITY_TOKEN=${SALESFORCE_SECURITY_TOKEN:-$5}
    SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}

    log "Login with sfdx CLI on the account #2"
    playground container exec --container sfdx-cli --command "sh -c \"sfdx sfpowerkit:auth:login -u \\\"$SALESFORCE_USERNAME\\\" -p \\\"$SALESFORCE_PASSWORD\\\" -r \\\"$SALESFORCE_INSTANCE\\\" -s \\\"$SALESFORCE_SECURITY_TOKEN\\\"\""

    log "Bulk delete leads"
    playground container exec --container sfdx-cli --command "sh -c \"sfdx data:query --target-org \\\"$SALESFORCE_USERNAME\\\" -q \\\"SELECT Id FROM Lead\\\" --result-format csv\" > /tmp/out.csv"
    docker cp /tmp/out.csv sfdx-cli:/tmp/out.csv
    playground container exec --container sfdx-cli --command "sh -c \"sfdx force:data:bulk:delete --target-org \\\"$SALESFORCE_USERNAME\\\" -s Lead -f /tmp/out.csv\""
fi

stop_all "$DIR"