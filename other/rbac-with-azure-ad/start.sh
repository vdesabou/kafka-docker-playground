#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "Replace create-role-bindings.sh (in order to specify superAdmin user password)"
cp $PWD/create-role-bindings.sh ../../environment/rbac-sasl-plain/scripts/helper/

log "Create truststore.jks from cert.pem"
rm -f truststore.jks
# https://docs.oracle.com/cd/E35976_01/server.740/es_admin/src/tadm_ssl_convert_pem_to_jks.html
keytool -genkey -keyalg RSA -alias endeca -keystore truststore.jks -noprompt -storepass confluent -keypass confluent -dname 'CN=broker,C=US'
keytool -delete -alias endeca -keystore truststore.jks -noprompt -storepass confluent -keypass confluent
keytool -import -v -trustcacerts -alias endeca-ca -file cert.cer -keystore truststore.jks -noprompt -storepass confluent -keypass confluent

#playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.rbac-with-azure-ad.yml"

#############

# https://docs.docker.com/compose/profiles/
profile_control_center_command=""
if [ -z "$ENABLE_CONTROL_CENTER" ]
then
  log "🛑 control-center is disabled"
else
  log "💠 control-center is enabled"
  log "Use http://localhost:9021 (superUser/Yoku5678) to login"
  profile_control_center_command="--profile control-center"
fi

profile_ksqldb_command=""
if [ -z "$ENABLE_KSQLDB" ]
then
  log "🛑 ksqldb is disabled"
else
  log "🚀 ksqldb is enabled"
  log "🔧 You can use ksqlDB with CLI using:"
  log "docker exec -i ksqldb-cli ksql http://ksqldb-server:8088"
  profile_ksqldb_command="--profile ksqldb"
fi

../../environment/rbac-sasl-plain/stop.sh $@

# Generating public and private keys for token signing
log "Generating public and private keys for token signing"
mkdir -p ../../environment/rbac-sasl-plain/conf
cd ../../environment/rbac-sasl-plain/
docker run -v $PWD:/tmp -u0 ${CP_KAFKA_IMAGE}:${TAG} bash -c "mkdir -p /tmp/conf; openssl genrsa -out /tmp/conf/keypair.pem 2048; openssl rsa -in /tmp/conf/keypair.pem -outform PEM -pubout -out /tmp/conf/public.pem && chown -R $(id -u $USER):$(id -g $USER) /tmp/conf && chmod 644 /tmp/conf/keypair.pem"
cd -


# Bring up base cluster and Confluent CLI
docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml -f "${PWD}/docker-compose.rbac-with-azure-ad.yml" up -d zookeeper broker tools openldap

sleep 5

log "Add the FQDN of LDAP server to broker /etc/hosts"
docker exec  --privileged --user root -i broker bash -c 'echo "20.86.237.230 ldaps.mydomain.onmicrosoft.com" >> /etc/hosts'

# Verify Kafka brokers have started
MAX_WAIT=30
log "⌛ Waiting up to $MAX_WAIT seconds for Kafka brokers to be registered in ZooKeeper"
retrycmd $MAX_WAIT 5 host_check_kafka_cluster_registered || exit 1

# Verify MDS has started
MAX_WAIT=120
log "⌛ Waiting up to $MAX_WAIT seconds for MDS to start"
retrycmd $MAX_WAIT 5 host_check_mds_up || exit 1
sleep 5

log "Creating role bindings for principals"
docker exec -i tools bash -c "/tmp/helper/create-role-bindings.sh"


docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml -f "${PWD}/docker-compose.rbac-with-azure-ad.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d
log "📝 To see the actual properties file, use cli command playground container get-properties -c <container>"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml -f ${DIR}/../../environment/rbac-sasl-plain/docker-compose.yml -f ${PWD}/docker-compose.rbac-with-azure-ad.yml ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d"
playground state set run.docker_command "$command"
playground state set run.environment "rbac-sasl-plain"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command playground container recreate"


wait_container_ready

display_jmx_info

#############

log "Add the FQDN of LDAP server to openldap (just in order to use ldapsearch) /etc/hosts"
docker exec -i openldap bash -c 'echo "20.86.237.230 ldaps.mydomain.onmicrosoft.com" >> /etc/hosts'
log "Modify /etc/ldap/ldap.conf to include TLS_CACERT"
docker exec -i openldap bash -c 'echo "TLS_CACERT /tmp/cert.txt" >> /etc/ldap/ldap.conf'

log "Do a ldap search for admin"
docker exec openldap ldapsearch -x -v  -H ldaps://ldaps.mydomain.onmicrosoft.com:636 -b "DC=mydomain,DC=onmicrosoft,DC=com" -D "CN=admin,OU=AADDC Users,DC=mydomain,DC=onmicrosoft,DC=com" -w 'Sugt5676'

log "Do a ldap search for ksqlDBAdmin"
docker exec openldap ldapsearch -x -v  -H ldaps://ldaps.mydomain.onmicrosoft.com:636 -b "DC=mydomain,DC=onmicrosoft,DC=com" -D "CN=ksqlDBAdmin,OU=AADDC Users,DC=mydomain,DC=onmicrosoft,DC=com" -w 'Yoco7654'

log "Do a ldap search for connectAdmin"
docker exec openldap ldapsearch -x -v  -H ldaps://ldaps.mydomain.onmicrosoft.com:636 -b "DC=mydomain,DC=onmicrosoft,DC=com" -D "CN=connectAdmin,OU=AADDC Users,DC=mydomain,DC=onmicrosoft,DC=com" -w 'UTu178cdd8'

log "Do a ldap search for schemaregistryUser"
docker exec openldap ldapsearch -x -v  -H ldaps://ldaps.mydomain.onmicrosoft.com:636 -b "DC=mydomain,DC=onmicrosoft,DC=com" -D "CN=schemaregistryUser,OU=AADDC Users,DC=mydomain,DC=onmicrosoft,DC=com" -w 'Tapu2399'

log "Do a ldap search for controlcenterAdmin"
docker exec openldap ldapsearch -x -v  -H ldaps://ldaps.mydomain.onmicrosoft.com:636 -b "DC=mydomain,DC=onmicrosoft,DC=com" -D "CN=controlcenterAdmin,OU=AADDC Users,DC=mydomain,DC=onmicrosoft,DC=com" -w 'Badu1234'

log "Do a ldap search for superUser"
docker exec openldap ldapsearch -x -v  -H ldaps://ldaps.mydomain.onmicrosoft.com:636 -b "DC=mydomain,DC=onmicrosoft,DC=com" -D "CN=superUser,OU=AADDC Users,DC=mydomain,DC=onmicrosoft,DC=com" -w 'Yoku5678'

log "Stopping now openldap container to make sure Azure AD is really used"
docker stop openldap