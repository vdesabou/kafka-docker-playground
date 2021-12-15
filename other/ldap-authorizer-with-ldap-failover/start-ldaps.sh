#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ${DIR}/ldap_certs
cd ${DIR}/ldap_certs
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
log "LDAPS: Creating a Root Certificate Authority (CA)"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"
log "LDAPS: Generate the LDAPS server key and certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=openldap"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt
log "LDAPS: Create a JKS truststore"
rm -f ldap_truststore.jks
# We import the test CA certificate
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -alias testroot -file /tmp/ca.crt -keystore /tmp/ldap_truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
log "LDAPS: Displaying truststore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/ldap_truststore.jks -storepass 'welcome123' -v
cd -

${DIR}/../../environment/ldap-authorizer-sasl-plain/start.sh "${PWD}/docker-compose.ldap-authorizer-sasl-plain.ldaps.yml"

# docker exec --privileged --user root -i broker yum install bind-utils

# nslookup -type=SRV _ldap._tcp.confluent.io
# Server:         127.0.0.11
# Address:        127.0.0.11#53

# _ldap._tcp.confluent.io  service = 10 50 389 ldap2.confluent.io.
# _ldap._tcp.confluent.io  service = 10 50 389 ldap.confluent.io.
# _ldap._tcp.confluent.io  service = 20 75 389 ldap3.confluent.io.


# [appuser@broker ~]$ dig SRV _ldap._tcp.confluent.io

# ; <<>> DiG 9.11.26-RedHat-9.11.26-6.el8 <<>> SRV _ldap._tcp.confluent.io
# ;; global options: +cmd
# ;; Got answer:
# ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 35223
# ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 3, AUTHORITY: 1, ADDITIONAL: 5

# ;; OPT PSEUDOSECTION:
# ; EDNS: version: 0, flags:; udp: 4096
# ; COOKIE: 6f8a2a347b2c1d044138bce361b8d3d6af6ba5f0aec87fc3 (good)
# ;; QUESTION SECTION:
# ;_ldap._tcp.confluent.io.                IN      SRV

# ;; ANSWER SECTION:
# _ldap._tcp.confluent.io. 604800  IN      SRV     10 50 389 ldap.confluent.io.
# _ldap._tcp.confluent.io. 604800  IN      SRV     20 75 389 ldap3.confluent.io.
# _ldap._tcp.confluent.io. 604800  IN      SRV     10 50 389 ldap2.confluent.io.

# ;; AUTHORITY SECTION:
# confluent.io.            604800  IN      NS      bind.confluent.io.

# ;; ADDITIONAL SECTION:
# ldap.confluent.io.       604800  IN      A       172.28.1.2
# ldap2.confluent.io.      604800  IN      A       172.28.1.7
# ldap3.confluent.io.      604800  IN      A       172.28.1.8
# bind.confluent.io.       604800  IN      A       172.28.1.1

# ;; Query time: 3 msec
# ;; SERVER: 127.0.0.11#53(127.0.0.11)
# ;; WHEN: Tue Dec 14 17:26:46 UTC 2021
# ;; MSG SIZE  rcvd: 272
