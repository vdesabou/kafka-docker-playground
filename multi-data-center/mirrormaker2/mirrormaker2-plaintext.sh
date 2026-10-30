#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "This example is working starting from CP 5.4 only"
    exit 111
fi

playground start-environment --environment mdc-plaintext --docker-compose-override-file "${PWD}/docker-compose.mdc-plaintext.yml"

log "Sending sales in Europe cluster"
playground topic produce --cluster europe --topic sales_EUROPE --nb-messages 10 --value "european_sale_%g ${RANDOM}"

log "Sending sales in US cluster"
playground topic produce --cluster us --topic sales_US --nb-messages 10 --value "us_sale_%g ${RANDOM}"

log "Consolidating all sales (logs are in /tmp/mirrormaker.log):"

# run in detach mode -d
docker exec -d connect-us bash -c '/usr/bin/connect-mirror-maker /etc/kafka/connect-mirror-maker.properties > /tmp/mirrormaker.log 2>&1'

# docker exec connect-us bash -c '/usr/bin/connect-mirror-maker /etc/kafka/connect-mirror-maker.properties'

# Topic Renaming

# By default MM2 renames source topics to be prefixed with the source cluster name. e.g. if topic foo came from cluster A then it would be named A.foo on the destination. In the current release (5.4) MM2 does not support any different topic naming strategies out of the box.

log "Verify we have received the data in topic US.sales_US in EUROPE"
playground topic wait-for-records --cluster europe --topic "US.sales_US" --min-expected-messages 10 --max-wait 180
playground topic consume --cluster europe --topic "US.sales_US" --min-expected-messages 10 --timeout 60

log "Verify we have received the data in topic EUROPE.sales_EUROPE topics in the US"
playground topic wait-for-records --cluster us --topic "EUROPE.sales_EUROPE" --min-expected-messages 10 --max-wait 180
playground topic consume --cluster us --topic "EUROPE.sales_EUROPE" --min-expected-messages 10 --timeout 60

log "Copying mirrormaker logs to /tmp/mirrormaker.log"
playground container cp --source connect-us:/tmp/mirrormaker.log --destination /tmp/mirrormaker.log