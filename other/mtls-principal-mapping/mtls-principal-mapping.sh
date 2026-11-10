#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "7.9.99"
then
  logwarn "This example uses the KRaft StandardAuthorizer of CP 8+"
  exit 111
fi

# mTLS: the broker turns the distinguished name of the client certificate into a principal with
# ssl.principal.mapping.rules, and the ACLs are on that principal. A certificate renewed with another
# distinguished name (OU=TEST → OU=PROD) no longer matches the rule: the principal becomes the full distinguished
# name, and the ACLs of the application stop applying

# created before the environment, so that docker does not create the mounted folder as root
mkdir -p "${DIR}/security"

playground start-environment --environment 2way-ssl --docker-compose-override-file "${PWD}/docker-compose.2way-ssl.yml"

# the CA of the environment is created by its start: the certificates of the application are created after it
function create_client_cert () {
  name="$1"
  dname="$2"
  log "🔐 certificate $name: $dname, signed by the CA of the environment"
  docker run --quiet --rm -u0 -v "${DIR}/../../environment/2way-ssl/security:/ca:ro" -v "${DIR}/security:/out" \
    -v "${DIR}/create-client-cert.bash:/create-client-cert.bash:ro" "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" \
    bash -c 'bash /create-client-cert.bash "$1" "$2" && chown -R "$3" /out' _ "$name" "$dname" "$(id -u):$(id -g)" > /tmp/mtls-principal-mapping-cert.log 2>&1 \
    || { cat /tmp/mtls-principal-mapping-cert.log; logerror "❌ could not create the certificate $name"; exit 1; }
}
create_client_cert orders-app "CN=orders-app,OU=TEST,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US"
create_client_cert orders-app-renewed "CN=orders-app,OU=PROD,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US"

# produce one record with the keystore of the application instead of the one of the client config the CLI uses
function produce_with () {
  keystore="$1"
  playground topic produce -t orders --nb-messages 1 --producer-property "ssl.keystore.location=/etc/kafka/app-secrets/kafka.${keystore}.keystore.jks" << 'EOF'
{"id": %g}
EOF
}

# ACLs reach the broker through the metadata log, and a changed broker takes a few seconds: retry before giving up
function expect_produce_allowed () {
  keystore="$1"
  for i in $(seq 1 6)
  do
    if produce_with "$keystore" > /tmp/mtls-principal-mapping-produce.log 2>&1
    then
      log "✅ the certificate $keystore can write to orders"
      return 0
    fi
    sleep 5
  done
  cat /tmp/mtls-principal-mapping-produce.log
  logerror "❌ the certificate $keystore should be allowed to write to orders"
  exit 1
}

function expect_produce_denied () {
  keystore="$1"
  for i in $(seq 1 6)
  do
    if ! produce_with "$keystore" > /tmp/mtls-principal-mapping-produce.log 2>&1
    then
      if grep -q "TopicAuthorizationException" /tmp/mtls-principal-mapping-produce.log
      then
        log "✅ the certificate $keystore is not authorized to write to orders (TopicAuthorizationException)"
        return 0
      fi
    fi
    sleep 5
  done
  cat /tmp/mtls-principal-mapping-produce.log
  logerror "❌ the certificate $keystore should get TopicAuthorizationException on orders"
  exit 1
}

# the principal of the last denied request, as the authorizer logged it
function expect_denied_principal () {
  expected="$1"
  denied=$(playground container logs -c broker --grep "is Denied operation = WRITE" --no-follow --tail 2000 2>&1 | grep "Principal = " | tail -1)
  echo "$denied"
  if [[ "$denied" != *"Principal = ${expected} "* ]]
  then
    logerror "❌ the broker should have denied ${expected}"
    exit 1
  fi
}

# raw kafka-acls on purpose: 'playground rbac acl' needs an RBAC environment, and this is what a customer runs
function kafka_acls () {
  playground container exec -c broker --command "kafka-acls --bootstrap-server broker:9092 --command-config /etc/kafka/secrets/client_without_interceptors.config $*"
}

playground topic create --topic orders

log "1️⃣ The ACLs of the application are on User:orders-app: the rule maps CN=orders-app,OU=TEST,… to orders-app"
kafka_acls --add --allow-principal User:orders-app --operation WRITE --operation DESCRIBE --topic orders
expect_produce_allowed orders-app

log "2️⃣ The certificate is renewed with OU=PROD: same CN, same CA, the TLS handshake still works"
playground tools cert inspect --file "${DIR}/security/kafka.orders-app-renewed.keystore.jks" --password confluent --output-dir /tmp/mtls-principal-mapping-cert-inspect | grep -iE "subject|CN=orders-app" | head -5 || true
expect_produce_denied orders-app-renewed

log "The rule ^CN=(.*?),OU=TEST.*$ no longer matches, DEFAULT keeps the whole distinguished name as principal"
expect_denied_principal "User:CN=orders-app,OU=PROD,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US"

log "3️⃣ Workaround: an ACL on the full distinguished name, no broker change"
kafka_acls --add --allow-principal "'User:CN=orders-app,OU=PROD,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US'" --operation WRITE --operation DESCRIBE --topic orders
expect_produce_allowed orders-app-renewed
kafka_acls --remove --force --allow-principal "'User:CN=orders-app,OU=PROD,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US'" --operation WRITE --operation DESCRIBE --topic orders
expect_produce_denied orders-app-renewed

log "4️⃣ Fix: a rule that matches both certificates. ssl.principal.mapping.rules is not a dynamic broker config: the broker is recreated"
set +e
playground broker config set --key ssl.principal.mapping.rules --value 'RULE:^CN=(.*?),OU=(TEST|PROD),.*$/$1/,DEFAULT' > /tmp/mtls-principal-mapping-config.log 2>&1
rc=$?
set -e
cat /tmp/mtls-principal-mapping-config.log
if [ $rc -eq 0 ]
then
  logerror "❌ ssl.principal.mapping.rules should not be updatable without a restart"
  exit 1
fi
# $$ is the docker compose escape of $
playground container set-environment-variables -c broker --env 'KAFKA_SSL_PRINCIPAL_MAPPING_RULES: RULE:^CN=(.*?),OU=(TEST|PROD),.*$$/$$1/,DEFAULT'
# set-environment-variables waits for connect: wait for the recreated broker too
playground broker health --wait-healthy --max-wait 180
playground container get-properties -c broker | grep "ssl.principal.mapping.rules"

log "The renewed certificate is orders-app again, the ACLs of the application apply to both certificates"
expect_produce_allowed orders-app-renewed
expect_produce_allowed orders-app
