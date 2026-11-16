#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/day2-utils.bash

# RBAC (MDS, LDAP) enabled on a running SASL_SSL cluster deployed by cp-ansible, in the order of cp-ansible's procedure
# (docs/sample_inventories/nonRBACtoRBACLdap.yml), with a workload running through it:
#   1. a client listener for the applications and the components, so that they keep working during the switch
#   2. RBAC on: the INTERNAL listener becomes OAUTHBEARER only (the one-step mistake: every SASL/PLAIN client on it is
#      locked out). The SASL/PLAIN principals of the components are super users during the transition (cp-ansible's
#      procedure gives them ACLs): cp-ansible creates role bindings on their resources (_schemas, connect-cluster-*)
#      for their LDAP users, not for their SASL/PLAIN users. An application with neither an ACL nor a role binding is
#      denied from now on: the classic mistake
#   3. role bindings for the applications and the connectors, then the components back on INTERNAL, with MDS tokens and
#      their LDAP users
#   4. the transition super users removed
day2_require_plaintext

function day2_mds () {
    # $1 method, $2 path, $3 json body (MDS REST API, as the MDS super user, from the broker host)
    docker exec broker curl -sk -u mds:mds-secret -X "$1" -H "Content-Type: application/json" ${3:+-d "$3"} "https://broker:8090$2"
}

function day2_role_binding () {
    # $1 principal, $2 role, $3 resource type, $4 resource name
    local cluster_id
    cluster_id=$(day2_mds GET /v1/metadata/id | jq -r .id)
    log "🔑 role binding: $1 $2 on $3:$4"
    day2_mds POST "/security/1.0/principals/$1/roles/$2/bindings" "{\"scope\": {\"clusters\": {\"kafka-cluster\": \"$cluster_id\"}}, \"resourcePatterns\": [{\"resourceType\": \"$3\", \"name\": \"$4\", \"patternType\": \"LITERAL\"}]}"
}

log "Step 1: a SASL_SSL cluster deployed by cp-ansible, 3 brokers, and an LDAP directory (openldap)"
ENABLE_KAFKA_NODES=1 playground start-environment --environment ansible-sasl-ssl --docker-compose-override-file "${DIR}/docker-compose.rbac.yml"
day2_start_workload
# a second application, as the SASL/PLAIN user 'client': nobody will give it a role binding
docker exec connect sh -c "sed 's/username=\"[^\"]*\" password=\"[^\"]*\"/username=\"client\" password=\"client-secret\"/' /etc/kafka/client.properties > /tmp/day2-client.properties"
day2_start_producer 9092 /tmp/day2-client.properties forgotten
sleep 10

log "Step 2: a client listener (9093, SASL/PLAIN over SSL) for the applications and the components, rolling"
playground ansible inventory set .all.vars.kafka_broker_custom_listeners '{"client": {"name": "CLIENT", "port": 9093, "ssl_enabled": true, "sasl_protocol": "plain"}}'
playground ansible inventory set .all.vars.kafka_connect_kafka_listener_name client
playground ansible inventory set .all.vars.schema_registry_kafka_listener_name client
playground ansible playbook --rolling
day2_stop_producer producer
day2_start_producer 9093 /etc/kafka/client.properties producer
day2_stop_producer forgotten
docker exec connect sh -c "sed 's/username=\"[^\"]*\" password=\"[^\"]*\"/username=\"client\" password=\"client-secret\"/' /etc/kafka/client.properties > /tmp/day2-client.properties"
day2_start_producer 9093 /tmp/day2-client.properties forgotten
sleep 15
day2_report_workload "on the client listener"
day2_report_workload "on the client listener" forgotten

log "Step 3: RBAC on (MDS, LDAP users of the components), the SASL/PLAIN users of the components as super users during the transition, rolling"
forgotten_errors_before=$(day2_send_errors forgotten)
ldap_properties='{
  "super.users": "User:admin;User:mds;User:kafka_connect;User:schema_registry",
  "ldap.java.naming.factory.initial": "com.sun.jndi.ldap.LdapCtxFactory",
  "ldap.com.sun.jndi.ldap.read.timeout": 3000,
  "ldap.java.naming.provider.url": "ldap://openldap:389",
  "ldap.java.naming.security.principal": "cn=admin,dc=confluentdemo,dc=io",
  "ldap.java.naming.security.credentials": "admin",
  "ldap.java.naming.security.authentication": "simple",
  "ldap.search.mode": "GROUPS",
  "ldap.group.search.base": "ou=groups,dc=confluentdemo,dc=io",
  "ldap.group.name.attribute": "cn",
  "ldap.group.member.attribute": "memberUid",
  "ldap.group.object.class": "posixGroup",
  "ldap.group.member.attribute.pattern": "cn=(.*),ou=users,dc=confluentdemo,dc=io",
  "ldap.user.search.base": "ou=users,dc=confluentdemo,dc=io",
  "ldap.user.name.attribute": "uid",
  "ldap.user.object.class": "inetOrgPerson"
}'
playground ansible inventory set .all.vars.kafka_broker_custom_properties "$ldap_properties"
playground ansible inventory set .all.vars.kafka_controller_custom_properties "$ldap_properties"
for kv in rbac_enabled=true mds_super_user=mds mds_super_user_password=mds-secret schema_registry_ldap_user=schema-registry1 schema_registry_ldap_password=schema-registry1-secret kafka_connect_ldap_user=kafka-connect1 kafka_connect_ldap_password=kafka-connect1-secret
do
    playground ansible inventory set ".all.vars.${kv%%=*}" "${kv#*=}"
done
playground ansible inventory set .all.vars.rbac_component_additional_system_admins '["mds"]'
playground ansible playbook --rolling
playground container get-properties -c broker | grep -E "^(listener.security.protocol.map|listener.name.internal.sasl.enabled.mechanisms|authorizer.class.name)="
day2_report_workload "after enabling RBAC"
day2_report_workload "after enabling RBAC (no ACL, no role binding)" forgotten
forgotten_errors=$(( $(day2_send_errors forgotten) - forgotten_errors_before ))
log "💥 the application nobody gave a role binding (User:client): $forgotten_errors send errors since RBAC is on, the last one:"
docker exec connect sh -c "grep '\"producer_send_error\"' /tmp/day2-forgotten.log | tail -1" | jq -r '.exception + ": " + .message' | cut -c1-200
day2_stop_producer forgotten

log "Step 4: role bindings for the producer and the sink connector, then the components back on the INTERNAL listener, with MDS tokens (their LDAP users), rolling"
day2_role_binding User:kafka_connect DeveloperWrite Topic "$DAY2_TOPIC"
# the sink runs as the worker's principal: kafka-connect1 once connect logs in with its LDAP user
day2_role_binding User:kafka-connect1 DeveloperRead Topic "$DAY2_TOPIC"
day2_role_binding User:kafka-connect1 DeveloperRead Group connect-day2-sink
playground ansible inventory delete .all.vars.kafka_connect_kafka_listener_name
playground ansible inventory delete .all.vars.schema_registry_kafka_listener_name
playground ansible playbook --rolling --limit kafka_connect,schema_registry
playground container get-properties -c connect | grep -E "^(bootstrap.servers|sasl.mechanism)="
playground connector status --connector day2-sink
day2_report_workload "components on tokens"

log "Step 5: the transition super users removed, rolling: the producer and the sink keep working with their role bindings"
playground ansible inventory set '.all.vars.kafka_broker_custom_properties["super.users"]' '"User:admin;User:mds"'
playground ansible playbook --rolling --limit kafka_broker
sleep 20
day2_report_workload "after removing the transition super users"
playground connector status --connector day2-sink

log "Step 6: no record lost"
day2_check_no_loss
if [ "$forgotten_errors" -eq 0 ]
then
    logerror "❌ the application without a role binding should be denied once RBAC is on"
    exit 1
fi
