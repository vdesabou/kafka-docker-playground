#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco
cd ../../connect/connect-jms-tibco-sink/docker-tibco/
get_3rdparty_file "TIB_ems-ce_8.5.1_linux_x86_64.zip"
cd -
if [ ! -f ../../connect/connect-jms-tibco-sink/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     logerror "ERROR: ../../connect/connect-jms-tibco-sink/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
     exit 1
fi

if [ ! -f ../../connect/connect-jms-tibco-sink/tibjms.jar ]
then
     log "../../connect/connect-jms-tibco-sink/tibjms.jar missing, will get it from ../../connect/connect-jms-tibco-sink/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ../../connect/connect-jms-tibco-sink/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
     cp ../../connect/connect-jms-tibco-sink/opt/tibco/ems/8.5/lib/tibjms.jar ../../connect/connect-jms-tibco-sink/
     rm -rf ../../connect/connect-jms-tibco-sink/opt
fi

if test -z "$(docker images -q tibems:latest)"
then
     log "Building TIBCO EMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ../../connect/connect-jms-tibco-sink/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:latest . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic sink-messages"
playground topic produce -t sink-messages --nb-messages 10 << 'EOF'
%g
EOF

log "Creating JMS TIBCO EMS sink connector"
playground connector create-or-update --connector jms-tibco-ems-sink << EOF
{
               "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
                    "tasks.max": "1",
                    "topics": "sink-messages",
                    "java.naming.provider.url": "tibjmsnaming://tibco-ems:7222",
                    "java.naming.factory.initial": "com.tibco.tibjms.naming.TibjmsInitialContextFactory",
                    "jndi.connection.factory": "QueueConnectionFactory",
                    "java.naming.security.principal": "admin",
                    "java.naming.security.credentials": "",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }
EOF

sleep 5


log "Verify we have received the data in connector-quickstart EMS queue"
docker exec -i tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgConsumer -user admin -queue connector-quickstart -nbmessages 10' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Text=" /tmp/result.log
