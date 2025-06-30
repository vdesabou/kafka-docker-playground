#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "1.1.99"
then
     logwarn "minimal supported connector version is 1.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# take since last 6 months
#SINCE=$(date -v-4320H "+%Y-%m-%d %H:%M")
SINCE="2021-01-01 00:00"

# log "Enable debug logging"
# curl -X PUT \
#      -H "Content-Type: application/json" \
#      -d '{"level": "DEBUG"}' \
#      http://localhost:8083/admin/loggers/org.apache.http.wire | jq .

log "Creating Jira Source connector"
playground connector create-or-update --connector jira-source  << EOF
{
                    "connector.class": "io.confluent.connect.jira.JiraSourceConnector",
                    "topic.name.pattern":"jira-topic-\${resourceName}",
                    "tasks.max": "1",
                    "jira.url": "$JIRA_URL",
                    "jira.since": "$SINCE",
                    "jira.username": "$JIRA_USERNAME",
                    "jira.api.token": "$JIRA_API_TOKEN",
                    "jira.tables": "issues",
                    "jira.resources": "issues",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }
EOF


sleep 10

log "Verify we have received the data in jira-topic-issues topic"
playground topic consume --topic jira-topic-issues --min-expected-messages 1 --timeout 60
