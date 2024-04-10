#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

JIRA_URL=${JIRA_URL:-$1}
JIRA_USERNAME=${JIRA_USERNAME:-$2}
JIRA_API_TOKEN=${JIRA_API_TOKEN:-$3}

if [ -z "$JIRA_URL" ]
then
     logerror "JIRA_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$JIRA_USERNAME" ]
then
     logerror "JIRA_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$JIRA_API_TOKEN" ]
then
     logerror "JIRA_API_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

bootstrap_ccloud_environment

set +e
playground topic delete --topic datalake_topic
sleep 3
playground topic create --topic datalake_topic --nb-partitions 1
set -e


connector_name="JiraSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "JiraSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "jira.url": "$JIRA_URL",
     "jira.since": "2021-01-01 00:00",
     "jira.username": "$JIRA_USERNAME",
     "jira.api.token": "$JIRA_API_TOKEN",
     "jira.tables": "issues",
     "jira.resources": "issues",
     "topic.name.pattern":"jira-topic-\${resourceName}",
     "output.data.format": "JSON",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

sleep 10

log "Verify we have received the data in jira-topic-issues topic"
playground topic consume --topic jira-topic-issues --min-expected-messages 1 --timeout 60
