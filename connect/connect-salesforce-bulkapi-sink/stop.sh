#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # running with github actions


    # second account (for Bulk API sink)
    SALESFORCE_USERNAME_ACCOUNT2=${SALESFORCE_USERNAME_ACCOUNT2:-$6}
    SALESFORCE_PASSWORD_ACCOUNT2=${SALESFORCE_PASSWORD_ACCOUNT2:-$7}
    SALESFORCE_SECURITY_TOKEN_ACCOUNT2=${SALESFORCE_SECURITY_TOKEN_ACCOUNT2:-$8}
    SALESFORCE_INSTANCE_ACCOUNT2=${SALESFORCE_INSTANCE_ACCOUNT2:-"https://login.salesforce.com"}

    log "Login with sfdx CLI on the account #2"
    playground container exec --container sfdx-cli --command "sh -c \"sfdx sfpowerkit:auth:login -u \\\"$SALESFORCE_USERNAME_ACCOUNT2\\\" -p \\\"$SALESFORCE_PASSWORD_ACCOUNT2\\\" -r \\\"$SALESFORCE_INSTANCE_ACCOUNT2\\\" -s \\\"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\\\"\""

    log "Bulk delete leads"
    playground container exec --container sfdx-cli --command "sh -c \"sfdx data:query --target-org \\\"$SALESFORCE_USERNAME_ACCOUNT2\\\" -q \\\"SELECT Id FROM Lead\\\" --result-format csv\" > /tmp/out.csv"
    docker cp /tmp/out.csv sfdx-cli:/tmp/out.csv
    playground container exec --container sfdx-cli --command "sh -c \"sfdx force:data:bulk:delete --target-org \\\"$SALESFORCE_USERNAME_ACCOUNT2\\\" -s Lead -f /tmp/out.csv\""
fi

stop_all "$DIR"