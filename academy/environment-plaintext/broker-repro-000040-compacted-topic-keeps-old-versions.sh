#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

# the profiles of the customers, the latest version of each key is what the profile service needs
log "Topic customer-profiles, compacted"
playground topic create --topic customer-profiles --nb-partitions 1 --config cleanup.policy=compact

log "📇 3 customers, each profile updated 5 times"
for version in 1 2 3 4 5
do
    for customer in c1 c2 c3
    do
        playground topic produce --topic customer-profiles --nb-messages 1 --key "$customer" --value "{\"customer\":\"$customer\",\"version\":$version}" --value-format raw > /dev/null
    done
done

log "⏳ a while later"
sleep 60

log "What the profile service reads when it rebuilds its cache"
playground topic consume --topic customer-profiles --min-expected-messages 15 --timeout 60
