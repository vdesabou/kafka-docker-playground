#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco
cd ../../connect/connect-tibco-source/docker-tibco/
get_3rdparty_file "TIB_ems-ce_8.5.1_linux_x86_64.zip"
cd -
if [ ! -f ../../connect/connect-tibco-source/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     logerror "ERROR: ../../connect/connect-tibco-source/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
     exit 1
fi

if [ ! -f ../../connect/connect-tibco-source/tibjms.jar ]
then
     log "../../connect/connect-tibco-source/tibjms.jar missing, will get it from ../../connect/connect-tibco-source/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ../../connect/connect-tibco-source/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
     cp ../../connect/connect-tibco-source/opt/tibco/ems/8.5/lib/tibjms.jar ../../connect/connect-tibco-source/
     rm -rf ../../connect/connect-tibco-source/opt
fi

if test -z "$(docker images -q tibems:latest)"
then
     log "Building TIBCO EMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ../../connect/connect-tibco-source/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:latest . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Sending EMS messages m1 m2 m3 m4 m5 in queue connector-quickstart"
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgProducer -user admin -queue connector-quickstart m1 m2 m3 m4 m5'


log "Creating TIBCO EMS source connector"
playground connector create-or-update --connector tibco-ems-source --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
               "connector.class": "io.confluent.connect.tibco.TibcoSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "from-tibco-messages",
                    "tibco.url": "tcp://tibco-ems:7222",
                    "tibco.username": "admin",
                    "tibco.password": "",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }
EOF

sleep 5


log "Verify we have received the data in from-tibco-messages topic"
playground topic consume --topic from-tibco-messages --min-expected-messages 2 --timeout 60
