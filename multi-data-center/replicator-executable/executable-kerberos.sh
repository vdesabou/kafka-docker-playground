#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    log "Removing rest.extension.classes from properties files, otherwise getting Failed to find any class that implements interface org.apache.kafka.connect.rest.ConnectRestExtension and which name matches io.confluent.connect.replicator.monitoring.ReplicatorMonitoringExtension"
    head -n -1 replication-europe.properties > /tmp/temp.properties ; mv /tmp/temp.properties replication-europe.properties
    head -n -1 replication-us.properties > /tmp/temp.properties ; mv /tmp/temp.properties replication-us.properties
fi

set +e
if version_gt $TAG_BASE "8.2.99"
then
    docker run --quiet --rm confluentinc/cp-enterprise-replicator-executable:${TAG} type microdnf > /dev/null 2>&1
    if [ $? != 0 ]
    then
      log "🛠️ Restoring ubi minimal into confluentinc/cp-enterprise-replicator-executable:${TAG}"
      pm_tmp_dir=$(mktemp -d -t pg-pm-XXXXXXXXXX)
      cat << EOF > $pm_tmp_dir/Dockerfile
FROM redhat/ubi9-minimal:latest AS pm
RUN rm -f /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/subuid /etc/subgid

FROM confluentinc/cp-enterprise-replicator-executable:${TAG}
USER root
COPY --from=pm / /
RUN ldconfig
USER appuser
EOF
      DOCKER_BUILDKIT=0 docker build -t confluentinc/cp-enterprise-replicator-executable:${TAG} $pm_tmp_dir
      rm -rf $pm_tmp_dir
    fi
fi
set -e


playground start-environment --environment mdc-kerberos --docker-compose-override-file "${PWD}/docker-compose.mdc-kerberos.replicator.yml"

log "Sending sales in Europe cluster"
playground topic produce --cluster europe --topic sales_EUROPE --nb-messages 10 --value "european_sale_%g ${RANDOM}"

log "Sending sales in US cluster"
playground topic produce --cluster us --topic sales_US --nb-messages 10 --value "us_sale_%g ${RANDOM}"

if version_gt $TAG_BASE "8.0.99"
then
    playground container exec --root --command "microdnf -y install krb5-workstation" -c replicator-europe
    playground container exec --root --command "microdnf -y install krb5-workstation" -c replicator-us
fi
playground container exec -c replicator-us --command "kinit -k -t /var/lib/secret/kafka-connect.key connect"
playground container exec -c replicator-europe --command "kinit -k -t /var/lib/secret/kafka-connect.key connect"

playground container restart -c replicator-europe
playground container restart -c replicator-us

wait_container_ready replicator-us
wait_container_ready replicator-europe

log "Verify we have received the US sales in EUROPE"
playground topic wait-for-records --cluster europe --topic sales_US --min-expected-messages 10 --max-wait 240
playground topic consume --cluster europe --topic sales_US --min-expected-messages 10 --timeout 60

log "Verify we have received the European sales in the US"
playground topic wait-for-records --cluster us --topic sales_EUROPE --min-expected-messages 10 --max-wait 240
playground topic consume --cluster us --topic sales_EUROPE --min-expected-messages 10 --timeout 60
