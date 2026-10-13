#!/bin/bash
# RBAC part of the cfk-rbac environment, sourced by environment/cfk/start.sh when CFK_ENVIRONMENT=cfk-rbac.
# Everything else (k3d, operator, connect plugins, extra pods, port-forwards) is shared with cfk.

CFK_RBAC_DIR="$( cd "${DIR}/../cfk-rbac" >/dev/null && pwd )"
RBAC_SASL_PLAIN_DIR="$( cd "${DIR}/../rbac-sasl-plain" >/dev/null && pwd )"

# same image and users as environment/rbac-sasl-plain
OPENLDAP_IMAGE="osixia/openldap:1.3.0"
export OPENLDAP_IMAGE

CFK_MANIFEST_TEMPLATE="${CFK_RBAC_DIR}/confluent-platform.yaml"

# kafka-* tools and curl calls made by start.sh inside connect-0
CFK_CONNECT_CURL_AUTH="-u superUser:superUser"

for cfk_rbac_unsupported_flag in ENABLE_CONTROL_CENTER ENABLE_KSQLDB ENABLE_RESTPROXY
do
  if [[ -n "${!cfk_rbac_unsupported_flag}" ]]
  then
    logwarn "⚠️ $cfk_rbac_unsupported_flag is not supported with cfk-rbac environment, ignoring it"
    unset "$cfk_rbac_unsupported_flag"
  fi
done

# usage: apply_cfk_rbac_secret <name> <key>=<value> [<key>=<value>...]
function apply_cfk_rbac_secret() {
  local name="$1"
  shift
  local from_literals=()
  local key_value
  for key_value in "$@"
  do
    from_literals+=(--from-literal="$key_value")
  done
  kubectl -n confluent create secret generic "$name" "${from_literals[@]}" --dry-run=client -o yaml | kubectl -n confluent apply -f - > /dev/null
}

# usage: cfk_rbac_user_password_file <user> <password>
function cfk_rbac_user_password_file() {
  printf 'username=%s\npassword=%s' "$1" "$2"
}

function deploy_cfk_rbac_prerequisites() {
  log "🔐 Create the RBAC secrets (credentials of the LDAP users of environment/rbac-sasl-plain)"

  # admin: super user, inter-broker, metrics reporter, KRaft controller, playground CLI
  apply_cfk_rbac_secret credential \
    "plain-users.json={\"admin\": \"admin-secret\"}" \
    "plain.txt=$(cfk_rbac_user_password_file admin admin-secret)" \
    "plain-interbroker.txt=$(cfk_rbac_user_password_file admin admin-secret)" \
    "ldap.txt=$(cfk_rbac_user_password_file cn=admin,dc=confluentdemo,dc=io admin)"
  apply_cfk_rbac_secret credential-plain \
    "plain-jaas.conf=sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"admin\" password=\"admin-secret\" user_admin=\"admin-secret\";"

  # key pair used by MDS to sign tokens, generated at every start like in rbac-sasl-plain (never committed)
  local mds_token_dir
  mds_token_dir=$(mktemp -d)
  chmod 777 "$mds_token_dir"
  docker run --quiet --rm -v "$mds_token_dir":/tmp -u0 alpine/openssl genrsa -out /tmp/keypair.pem 2048 > /dev/null 2>&1
  docker run --quiet --rm -v "$mds_token_dir":/tmp -u0 alpine/openssl rsa -in /tmp/keypair.pem -outform PEM -pubout -out /tmp/public.pem > /dev/null 2>&1
  if [[ ! -s "$mds_token_dir/public.pem" ]]
  then
    logerror "❌ Could not generate the MDS token key pair with alpine/openssl"
    exit 1
  fi
  kubectl -n confluent create secret generic mds-token \
    --from-file=mdsPublicKey.pem="$mds_token_dir/public.pem" \
    --from-file=mdsTokenKeyPair.pem="$mds_token_dir/keypair.pem" \
    --dry-run=client -o yaml | kubectl -n confluent apply -f - > /dev/null
  rm -rf "$mds_token_dir"

  # embedded REST proxy of Kafka, and KafkaRestClass used by CFK to manage topics and role bindings
  apply_cfk_rbac_secret mds-client-kafka-rest "bearer.txt=$(cfk_rbac_user_password_file admin admin-secret)"
  apply_cfk_rbac_secret rest-credential "bearer.txt=$(cfk_rbac_user_password_file admin admin-secret)"

  # components
  apply_cfk_rbac_secret kafka-client-connect "plain.txt=$(cfk_rbac_user_password_file connectAdmin connectAdmin)"
  apply_cfk_rbac_secret mds-client-connect "bearer.txt=$(cfk_rbac_user_password_file connectAdmin connectAdmin)"
  apply_cfk_rbac_secret kafka-client-sr "plain.txt=$(cfk_rbac_user_password_file schemaregistryUser schemaregistryUser)"
  apply_cfk_rbac_secret mds-client-sr "bearer.txt=$(cfk_rbac_user_password_file schemaregistryUser schemaregistryUser)"

  # Connector resources created by 'playground connector create-or-update'
  apply_cfk_rbac_secret connector-submitter "bearer.txt=$(cfk_rbac_user_password_file connectorSubmitter connectorSubmitter)"

  # kafka-* tools of the playground CLI, run in connect-0
  apply_cfk_rbac_secret playground-client \
    "client.properties=$(printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=PLAIN\nsasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";\n')"

  log "👥 Deploy OpenLDAP"
  kubectl -n confluent create configmap openldap-ldifs \
    --from-file="${RBAC_SASL_PLAIN_DIR}/scripts/security/ldap_users" \
    --dry-run=client -o yaml | kubectl -n confluent apply -f - > /dev/null
  envsubst '${OPENLDAP_IMAGE}' < "${CFK_RBAC_DIR}/openldap.yaml" | kubectl -n confluent apply -f -

  # MDS and the Kafka internal listener need LDAP at startup
  if ! kubectl -n confluent rollout status statefulset/openldap --timeout=300s
  then
    logerror "❌ OpenLDAP did not become ready in 300 seconds"
    kubectl -n confluent logs openldap-0 --tail=50 || true
    exit 1
  fi
}

# connect and schema-registry need MDS at startup: without this, they crash loop until kafka is up, and the
# growing back-off delays them by minutes
# usage: deploy_cfk_rbac_kafka_first <CFK manifest file>
function deploy_cfk_rbac_kafka_first() {
  local manifest_file="$1"
  local max_wait=600
  local cur_wait=0

  log "🚀 Deploy the KRaft controller and Kafka first, MDS has to be up before connect and schema-registry start"
  awk '
    function emit_doc(d) {
      if (d ~ /(^|\n)kind:[[:space:]]*(KRaftController|Kafka|KafkaRestClass)[[:space:]]*(\n|$)/) {
        print "---"
        printf "%s", d
      }
    }
    /^---[[:space:]]*$/ { emit_doc(doc); doc = ""; next }
    { doc = doc $0 "\n" }
    END { emit_doc(doc) }
  ' "$manifest_file" | kubectl apply -f -

  log "⌛ Waiting up to $max_wait seconds for pod kafka-0"
  set +e
  while ! kubectl -n confluent wait --for=condition=Ready pod/kafka-0 --timeout=5s > /dev/null 2>&1
  do
    # seen once after a namespace reset: the operator never reconciled the Kafka resource again, while the
    # KRaft controller was ready. A change of annotation triggers a new reconciliation
    if (( cur_wait > 0 && cur_wait % 60 == 0 )) && ! kubectl -n confluent get pod kafka-0 > /dev/null 2>&1
    then
      kubectl -n confluent annotate kafka kafka playground/reconcile="$(date +%s)" --overwrite > /dev/null 2>&1
    fi
    cur_wait=$(( cur_wait + 10 ))
    if [[ "$cur_wait" -ge "$max_wait" ]]
    then
      logerror "❌ kafka-0 did not become ready in $max_wait seconds"
      kubectl -n confluent get pods || true
      kubectl -n confluent get kraftcontroller,kafka -o wide || true
      exit 1
    fi
    sleep 5
  done
  set -e
  log "✅ kafka-0 is ready"
}

function apply_cfk_rbac_role_bindings() {
  log "🛡️ Create the default role bindings (ConfluentRolebinding resources of ${CFK_RBAC_DIR}/role-bindings.yaml)"
  kubectl -n confluent apply -f "${CFK_RBAC_DIR}/role-bindings.yaml"
}

# role bindings are created through the KafkaRestClass once Kafka is up, wait for them before an example
# creates its connectors
function wait_cfk_rbac_role_bindings() {
  local max_wait=300
  local cur_wait=0
  local not_created
  log "⌛ Waiting up to $max_wait seconds for the role bindings to be created in MDS"
  set +e
  while true
  do
    not_created=$(kubectl -n confluent get confluentrolebinding -o json 2>/dev/null | jq -r '.items[] | select(.status.state != "CREATED") | .metadata.name')
    if [[ -z "$not_created" ]] && kubectl -n confluent get confluentrolebinding -o name 2>/dev/null | grep -q .
    then
      break
    fi
    cur_wait=$(( cur_wait + 5 ))
    if [[ "$cur_wait" -ge "$max_wait" ]]
    then
      logerror "❌ Role bindings not created after $max_wait seconds: $(echo $not_created)"
      kubectl -n confluent get confluentrolebinding || true
      exit 1
    fi
    sleep 5
  done
  set -e
  log "✅ Role bindings are created"
}
