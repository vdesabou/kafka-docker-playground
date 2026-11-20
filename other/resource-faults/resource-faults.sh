#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
if [ "$PLAYGROUND_ENVIRONMENT" != "plaintext" ]
then
    logwarn "this example needs the plaintext environment (docker update, a tmpfs log dir for the broker)"
    exit 111
fi

playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Step 1: the limits and the usage of connect and broker"
playground debug resources --container connect --container broker

log "Step 2: connect gets half a cpu, then less memory than it uses: the kernel kills it (OOM)"
playground debug resources --container connect --cpus 0.5
playground debug resources --container connect --memory 300m
MAX_WAIT=120
CUR_WAIT=0
while ! playground debug resources --container connect 2>&1 | grep -q "OOM kill"
do
    sleep 5
    CUR_WAIT=$(( CUR_WAIT + 5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ connect was not OOM killed after $MAX_WAIT seconds with a 300m memory limit"
        exit 1
    fi
done
playground debug resources --container connect

log "Step 3: back to the original limits, connect starts again"
playground debug resources --container connect --reset
playground container wait-for-connect-rest-api-ready --max-wait 300

log "Step 4: the log dir of the broker (a 1g tmpfs) is filled to 100%: the next records cannot be written"
playground topic create --topic disk-full
playground topic produce -t disk-full --nb-messages 10 --value 'before-%g'
playground debug resources --container broker --fill-disk 100%
set +e
playground topic produce -t disk-full --nb-messages 10 --value 'after-%g'
set -e
playground container logs --container broker --wait-for-log "No space left on device" --max-wait 180
playground debug resources --container broker --reset
