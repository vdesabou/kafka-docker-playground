#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# MDS centralized ACLs: stored in the _confluent-metadata-auth topic, managed with the MDS REST API
# (playground rbac acl), enforced by the CONFLUENT access rule provider of the ConfluentServerAuthorizer
playground start-environment --environment rbac-sasl-plain

# produce one record as an LDAP user of the environment (password = user name for appSA and badapp),
# instead of the admin user of the client config the CLI uses
function produce_as () {
  user="$1"
  topic="$2"
  playground topic produce -t "$topic" --nb-messages 1 --producer-property "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$user\" password=\"$user\";" << 'EOF'
{"id": %g}
EOF
}

# ACLs reach the brokers through _confluent-metadata-auth: retry for a few seconds before giving up
function expect_produce_allowed () {
  user="$1"
  topic="$2"
  for i in $(seq 1 6)
  do
    if produce_as "$user" "$topic" > /tmp/centralized-acls-produce.log 2>&1
    then
      log "✅ User:$user can write to $topic"
      return 0
    fi
    sleep 5
  done
  cat /tmp/centralized-acls-produce.log
  logerror "❌ User:$user should be allowed to write to $topic"
  exit 1
}

function expect_produce_denied () {
  user="$1"
  topic="$2"
  for i in $(seq 1 6)
  do
    if ! produce_as "$user" "$topic" > /tmp/centralized-acls-produce.log 2>&1
    then
      if grep -q "TopicAuthorizationException" /tmp/centralized-acls-produce.log
      then
        log "✅ User:$user is not authorized to write to $topic (TopicAuthorizationException)"
        return 0
      fi
    fi
    sleep 5
  done
  cat /tmp/centralized-acls-produce.log
  logerror "❌ User:$user should get TopicAuthorizationException on $topic"
  exit 1
}

playground topic create --topic acl-demo
playground topic create --topic acl-deny
playground topic create --topic acl-group

log "1️⃣ User:appSA has no role binding and no ACL: it can't write"
expect_produce_denied appSA acl-demo

log "Creating centralized ACLs ALLOW WRITE and DESCRIBE for User:appSA on Topic:acl-demo (MDS REST API)"
playground rbac acl create --principal User:appSA --operation WRITE --operation DESCRIBE --resource Topic:acl-demo
expect_produce_allowed appSA acl-demo

log "2️⃣ playground rbac acl list shows the store of each ACL: centralized (MDS) or kafka-acls"
playground rbac acl list --principal User:appSA

log "kafka-acls --list only shows the ACLs of the ZK_ACL / KRAFT_ACL provider: the centralized ACLs of User:appSA are not there"
# raw kafka-acls on purpose: this is what a customer runs to check the ACLs
kafka_acls_output=$(playground container exec -c broker --command "kafka-acls --bootstrap-server broker:9092 --command-config /etc/kafka/secrets/client_without_interceptors.config --list --principal User:appSA" 2>&1)
echo "$kafka_acls_output"
if echo "$kafka_acls_output" | grep -q "principal=User:appSA"
then
  logerror "❌ kafka-acls --list should not show the centralized ACLs of User:appSA"
  exit 1
fi

log "3️⃣ A DENY ACL wins over a role binding"
playground rbac role-binding create --principal User:appSA --role DeveloperWrite --resource Topic:acl-deny
expect_produce_allowed appSA acl-deny

playground rbac acl create --principal User:appSA --operation WRITE --resource Topic:acl-deny --deny
expect_produce_denied appSA acl-deny

playground rbac acl delete --principal User:appSA --operation WRITE --resource Topic:acl-deny --deny
expect_produce_allowed appSA acl-deny

log "4️⃣ Centralized ACLs on an LDAP group: User:appSA is in the KafkaDevelopers group, User:badapp is not"
playground rbac acl create --principal Group:KafkaDevelopers --operation WRITE --operation DESCRIBE --resource Topic:acl-group
expect_produce_allowed appSA acl-group
expect_produce_denied badapp acl-group

log "A regular Kafka ACL (kafka-acls, --kafka-acls) for User:badapp: both stores are enforced together"
playground rbac acl create --principal User:badapp --operation WRITE --operation DESCRIBE --resource Topic:acl-group --kafka-acls
expect_produce_allowed badapp acl-group

playground rbac acl list
