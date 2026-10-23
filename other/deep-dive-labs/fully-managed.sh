#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# replays the lab of docs/deep-dive-fully-managed.md on Confluent Cloud (billed: a Datagen connector for a few minutes,
# deleted at the end). Skipped when Confluent Cloud is not available: no confluent CLI, not logged in, or on CI without
# CONFLUENT_CLOUD_EMAIL / CONFLUENT_CLOUD_PASSWORD
if ! command -v confluent > /dev/null 2>&1 && [ -z "$GITHUB_RUN_NUMBER" ]
then
    logwarn "the confluent CLI is not installed, skipping the fully managed lab"
    exit 111
fi
if [ -n "$GITHUB_RUN_NUMBER" ]
then
    if [ -z "$CONFLUENT_CLOUD_EMAIL" ] || [ -z "$CONFLUENT_CLOUD_PASSWORD" ]
    then
        logwarn "CONFLUENT_CLOUD_EMAIL / CONFLUENT_CLOUD_PASSWORD are not set, skipping the fully managed lab"
        exit 111
    fi
elif confluent kafka cluster list 2>&1 | grep -q -e "You must login to run that command" -e "Your session has expired"
then
    logwarn "the confluent CLI is not logged in (confluent login), skipping the fully managed lab"
    exit 111
fi

connector_name="LabDatagen_$USER"
topic="lab_pageviews_$USER"
function cleanup_fully_managed_lab () {
    set +e
    playground connector delete --connector "$connector_name" > /dev/null 2>&1
    playground topic delete --topic "$topic" > /dev/null 2>&1
    set -e
}
trap cleanup_fully_managed_lab EXIT

log "Step 1: the cluster, and a topic"
bootstrap_ccloud_environment
set +e
playground topic delete --topic "$topic" > /dev/null 2>&1
set -e
playground topic create --topic "$topic" --nb-partitions 1

log "Step 2: a connector of your own, waited for"
lab_run playground connector create-or-update --connector "$connector_name" --wait << EOF
{
  "connector.class": "DatagenSource",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "kafka.topic": "$topic",
  "output.data.format": "JSON",
  "quickstart": "PAGEVIEWS",
  "max.interval": "1000",
  "tasks.max": "1"
}
EOF
lab_expect_exit 0
lab_run playground connector status --connector "$connector_name"
lab_expect_exit 0
lab_expect_contains "$connector_name"
lab_expect_contains "RUNNING"
lab_run playground topic consume --topic "$topic" --min-expected-messages 5 --timeout 120
lab_expect_exit 0

log "Step 3: what you can see without a worker"
lab_run playground connector error-recommendations --connector "$connector_name"
lab_expect_exit 0
lab_run playground connector show-config --connector "$connector_name" --force-rest-endpoint
lab_expect_exit 0
lab_expect_contains "DatagenSource"
lab_expect_not_contains "$CLOUD_SECRET" "the API secret is not printed by the API"

log "Step 4: clean up"
lab_run playground connector delete --connector "$connector_name"
lab_expect_exit 0

log "✅ all the outputs of the page are as expected"
