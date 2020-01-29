#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating SNMP Source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "io.confluent.connect.snmp.SnmpSourceConnector",
                    "kafka.topic": "snmp-kafka-topic",
                    "snmp.v3.enabled": "true",
                    "snmp.batch.size": "50",
                    "snmp.listen.address": "0.0.0.0",
                    "snmp.listen.port": "10161",
                    "auth.password":"myauthpassword",
                    "privacy.password":"myprivacypassword",
                    "security.name":"mysecurityname",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/snmp-source/config | jq_docker_cli .


sleep 10

# USAGE: snmptrap [OPTIONS] AGENT TRAP-PARAMETERS

#   Version:  5.7.3
#   Web:      http://www.net-snmp.org/
#   Email:    net-snmp-coders@lists.sourceforge.net

# OPTIONS:
#   -h, --help            display this help message
#   -H                    display configuration file directives understood
#   -v 1|2c|3             specifies SNMP version to use
#   -V, --version         display package version number
# SNMP Version 1 or 2c specific
#   -c COMMUNITY          set the community string
# SNMP Version 3 specific
#   -a PROTOCOL           set authentication protocol (MD5|SHA)
#   -A PASSPHRASE         set authentication protocol pass phrase
#   -e ENGINE-ID          set security engine ID (e.g. 800000020109840301)
#   -E ENGINE-ID          set context engine ID (e.g. 800000020109840301)
#   -l LEVEL              set security level (noAuthNoPriv|authNoPriv|authPriv)
#   -n CONTEXT            set context name (e.g. bridge1)
#   -u USER-NAME          set security name (e.g. bert)
#   -x PROTOCOL           set privacy protocol (DES|AES)
#   -X PASSPHRASE         set privacy protocol pass phrase
#   -Z BOOTS,TIME         set destination engine boots/time
# General communication options
#   -r RETRIES            set the number of retries
#   -t TIMEOUT            set the request timeout (in seconds)
# Debugging
#   -d                    dump input/output packets in hexadecimal
#   -D[TOKEN[,...]]       turn on debugging output for the specified TOKENs
#                            (ALL gives extremely verbose debugging output)
# General options
#   -m MIB[:...]          load given list of MIBs (ALL loads everything)
#   -M DIR[:...]          look in given list of directories for MIBs
#     (default: /root/.snmp/mibs:/usr/share/snmp/mibs:/usr/share/snmp/mibs/iana:/usr/share/snmp/mibs/ietf:/usr/share/mibs/site:/usr/share/snmp/mibs:/usr/share/mibs/iana:/usr/share/mibs/ietf:/usr/share/mibs/netsnmp)
#   -P MIBOPTS            Toggle various defaults controlling MIB parsing:
#                           u:  allow the use of underlines in MIB symbols
#                           c:  disallow the use of "--" to terminate comments
#                           d:  save the DESCRIPTIONs of the MIB objects
#                           e:  disable errors when MIB symbols conflict
#                           w:  enable warnings when MIB symbols conflict
#                           W:  enable detailed warnings when MIB symbols conflict
#                           R:  replace MIB symbols from latest module
#   -O OUTOPTS            Toggle various defaults controlling output display:
#                           0:  print leading 0 for single-digit hex characters
#                           a:  print all strings in ascii format
#                           b:  do not break OID indexes down
#                           e:  print enums numerically
#                           E:  escape quotes in string indices
#                           f:  print full OIDs on output
#                           n:  print OIDs numerically
#                           q:  quick print for easier parsing
#                           Q:  quick print with equal-signs
#                           s:  print only last symbolic element of OID
#                           S:  print MIB module-id plus last element
#                           t:  print timeticks unparsed as numeric integers
#                           T:  print human-readable text along with hex strings
#                           u:  print OIDs using UCD-style prefix suppression
#                           U:  don't print units
#                           v:  print values only (not OID = value)
#                           x:  print all strings in hex format
#                           X:  extended index format
#   -I INOPTS             Toggle various defaults controlling input parsing:
#                           b:  do best/regex matching to find a MIB node
#                           h:  don't apply DISPLAY-HINTs
#                           r:  do not check values for range/type legality
#                           R:  do random access to OID labels
#                           u:  top-level OIDs must have '.' prefix (UCD-style)
#                           s SUFFIX:  Append all textual OIDs with SUFFIX before parsing
#                           S PREFIX:  Prepend all textual OIDs with PREFIX before parsing
#   -L LOGOPTS            Toggle various defaults controlling logging:
#                           e:           log to standard error
#                           o:           log to standard output
#                           n:           don't log at all
#                           f file:      log to the specified file
#                           s facility:  log to syslog (via the specified facility)

#                           (variants)
#                           [EON] pri:   log to standard error, output or /dev/null for level 'pri' and above
#                           [EON] p1-p2: log to standard error, output or /dev/null for levels 'p1' to 'p2'
#                           [FS] pri token:    log to file/syslog for level 'pri' and above
#                           [FS] p1-p2 token:  log to file/syslog for levels 'p1' to 'p2'
#   -C APPOPTS            Set various application specific behaviour:
#                           i:  send an INFORM instead of a TRAP

#   -v 1 TRAP-PARAMETERS:
#          enterprise-oid agent trap-type specific-type uptime [OID TYPE VALUE]...
#   or
#   -v 2 TRAP-PARAMETERS:
#          uptime trapoid [OID TYPE VALUE] ...

log "Test with SNMP v3 trap"
docker exec snmptrap snmptrap -v 3 -c public -u mysecurityname -a MD5 -A myauthpassword -x DES -X myprivacypassword connect:10161 '' 1.3.6.1.4.1.8072.2.3.0.1 1.3.6.1.4.1.8072.2.3.2.1 i 123456

sleep 5

log "Verify we have received the data in snmp-kafka-topic topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic snmp-kafka-topic --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 1