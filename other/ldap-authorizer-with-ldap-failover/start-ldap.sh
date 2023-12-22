#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment ldap-authorizer-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.ldap-authorizer-sasl-plain.ldap.yml"

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
