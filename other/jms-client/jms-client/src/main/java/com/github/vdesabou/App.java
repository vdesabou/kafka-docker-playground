package com.github.vdesabou;

import java.util.Properties;
import javax.jms.Connection;
import javax.jms.ConnectionFactory;
import javax.jms.Destination;
import javax.jms.JMSException;
import javax.jms.Message;
import javax.jms.MessageConsumer;
import javax.jms.MessageProducer;
import javax.jms.Session;
import javax.jms.TextMessage;
import io.confluent.kafka.jms.JMSClientConfig;
import io.confluent.kafka.jms.KafkaConnectionFactory;

public class App {

    public static void main(String[] args) throws JMSException {
        Properties settings = new Properties();
        settings.put(JMSClientConfig.CLIENT_ID_CONFIG, "jms-client");
        settings.put(JMSClientConfig.BOOTSTRAP_SERVERS_CONFIG, System.getenv("BOOTSTRAP_SERVERS"));
        settings.put(JMSClientConfig.ZOOKEEPER_CONNECT_CONF, System.getenv("ZOOKEEPER_CONNECT"));

        if(!System.getenv("USERNAME").equals("")) {
            // SASL_SSL environment is used
            settings.put("security.protocol", "SASL_SSL");
            settings.put("sasl.mechanism", "PLAIN");
            settings.put("sasl.jaas.config", "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"" + System.getenv("USERNAME") + "\" password=\"" + System.getenv("PASSWORD") + "\";");

            settings.put("ssl.truststore.location", "/etc/kafka/secrets/kafka.client.truststore.jks");
            settings.put("ssl.truststore.password", "confluent");

            // 2 way ssl: not required
            // settings.put("ssl.keystore.location", "/etc/kafka/secrets/kafka.client.keystore.jks");
            // settings.put("ssl.keystore.password", "confluent");
            // settings.put("ssl.key.password", "confluent");
        }
        ConnectionFactory connectionFactory = new KafkaConnectionFactory(settings);
        Connection connection = connectionFactory.createConnection();
        Session session = connection.createSession(false, Session.AUTO_ACKNOWLEDGE);
        Destination testQueue = session.createQueue("test-queue");


        MessageProducer producer = session.createProducer(testQueue);
        for (int i=0; i<50; i++) {
            TextMessage message = session.createTextMessage();
            message.setText("This is a text message " + i);
            producer.send(message);
        }

        int counter = 1;
        MessageConsumer consumer = session.createConsumer(testQueue);
        while (counter <= 40) {
            TextMessage message = (TextMessage)consumer.receive();
            System.out.println(message.getText());
            counter++;
        }
    }
}