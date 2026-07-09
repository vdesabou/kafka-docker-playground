#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CONNECTOR_GITHUB_ACCESS_TOKEN=${CONNECTOR_GITHUB_ACCESS_TOKEN:-$1}
CONNECTOR_GITHUB_REPOSITORIES=${CONNECTOR_GITHUB_REPOSITORIES:-"apache/kafka"}

if [ -z "$CONNECTOR_GITHUB_ACCESS_TOKEN" ]
then
     logerror "CONNECTOR_GITHUB_ACCESS_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

bootstrap_ccloud_environment

set +e
playground topic delete --topic github-topic-commits
sleep 3
playground topic create --topic github-topic-commits --nb-partitions 1
set -e


connector_name="GithubSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "GithubSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "github.service.url":"https://api.github.com",
    "github.repositories":"$CONNECTOR_GITHUB_REPOSITORIES",
    "github.resources":"commits",
    "github.since":"2019-01-01",
    "github.access.token": "$CONNECTOR_GITHUB_ACCESS_TOKEN",
    "topic.name.pattern":"github-topic-\${resourceName}",
    "output.data.format": "AVRO",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify we have received the data in github-topic-commits topic"
playground topic consume --topic github-topic-commits --min-expected-messages 1 --timeout 60