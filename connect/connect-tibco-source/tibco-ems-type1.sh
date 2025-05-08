#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Configuration with defaults
TASKS_MAX=${TASKS_MAX:-"2"}
NUM_MESSAGES=${NUM_MESSAGES:-"100"}

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco
cd ../../connect/connect-tibco-source/docker-tibco/
get_3rdparty_file "TIB_ems-ce_8.5.1_linux_x86_64.zip"
cd -
if [ ! -f ../../connect/connect-tibco-source/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     logerror "❌ ../../connect/connect-tibco-source/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
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


log "Sending ${NUM_MESSAGES} EMS messages to queue connector-quickstart"
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH

# Create a custom message producer for our specific needs
cat > DynamicMessageProducer.java << EOL
import javax.jms.*;
import com.tibco.tibjms.TibjmsConnectionFactory;

public class DynamicMessageProducer {
    public static void main(String[] args) {
        String serverUrl = "tcp://localhost:7222";
        String username = "admin";
        String password = "";
        String queueName = "connector-quickstart";
        
        if (args.length < 1) {
            System.out.println("Usage: java DynamicMessageProducer <numMessages>");
            System.exit(1);
        }
        
        try {
            int numMessages = Integer.parseInt(args[0]);
            
            ConnectionFactory factory = new TibjmsConnectionFactory(serverUrl);
            Connection connection = factory.createConnection(username, password);
            Session session = connection.createSession(false, Session.AUTO_ACKNOWLEDGE);
            Destination destination = session.createQueue(queueName);
            MessageProducer producer = session.createProducer(destination);
            
            connection.start();
            
            for (int i = 1; i <= numMessages; i++) {
                String messageContent = "Message-" + i;
                TextMessage message = session.createTextMessage(messageContent);
                producer.send(message);
                System.out.println("Sent message: " + messageContent);
            }
            
            connection.close();
            System.out.println("Successfully sent " + numMessages + " messages");
        } catch (NumberFormatException e) {
            System.out.println("Error: Number of messages must be an integer");
            e.printStackTrace();
        } catch (JMSException e) {
            System.out.println("JMS Error occurred");
            e.printStackTrace();
        }
    }
}
EOL

# Compile and run the dynamic producer
javac DynamicMessageProducer.java
java DynamicMessageProducer '"$NUM_MESSAGES"''


log "Creating TIBCO EMS source connector"
playground connector create-or-update --connector tibco-ems-source  << EOF
{
               "connector.class": "io.confluent.connect.tibco.TibcoSourceConnector",
                    "tasks.max": "$TASKS_MAX",
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
playground topic consume --topic from-tibco-messages --min-expected-messages $NUM_MESSAGES --timeout 60
