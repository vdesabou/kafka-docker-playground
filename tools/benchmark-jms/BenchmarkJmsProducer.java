import java.util.Hashtable;

import javax.jms.Connection;
import javax.jms.ConnectionFactory;
import javax.jms.DeliveryMode;
import javax.jms.Destination;
import javax.jms.MessageProducer;
import javax.jms.Session;
import javax.naming.Context;
import javax.naming.InitialContext;

/**
 * Sends text messages to a JMS queue or topic, for the load of 'playground connector benchmark'.
 *
 * Uses only the JMS 1.1 API, so it runs with the client jars of any provider (weblogic, tibco...), looked up with the
 * same JNDI settings as the connector (java.naming.*, connection.factory.name). The destination is created from its
 * physical name (Session.createQueue / createTopic), like the JMS source connectors do.
 *
 * Arguments: <jndi factory> <provider url> <principal or ""> <credentials or ""> <connection factory name>
 *            <queue|topic> <destination name> <messages> <record size> <transaction batch size, 0 for none>
 * With -Dbenchmark.json=<template>, the messages are the template with {message} replaced by "benchmark message <i>",
 * for a connector parsing json (-Dbenchmark.json=true: {"f1":"{message}"}).
 */
public class BenchmarkJmsProducer {

    public static void main(String[] args) throws Exception {
        if (args.length != 10) {
            System.err.println("usage: BenchmarkJmsProducer <jndi factory> <provider url> <principal> <credentials> "
                    + "<connection factory> <queue|topic> <destination> <messages> <record size> <transaction batch size>");
            System.exit(1);
        }
        Hashtable<String, String> env = new Hashtable<>();
        env.put(Context.INITIAL_CONTEXT_FACTORY, args[0]);
        env.put(Context.PROVIDER_URL, args[1]);
        if (!args[2].isEmpty()) {
            env.put(Context.SECURITY_PRINCIPAL, args[2]);
            env.put(Context.SECURITY_CREDENTIALS, args[3]);
        }
        String destinationType = args[5];
        String destinationName = args[6];
        int messages = Integer.parseInt(args[7]);
        int recordSize = Integer.parseInt(args[8]);
        int batch = Integer.parseInt(args[9]);

        Context context = new InitialContext(env);
        ConnectionFactory factory = (ConnectionFactory) context.lookup(args[4]);
        Connection connection = args[2].isEmpty() ? factory.createConnection() : factory.createConnection(args[2], args[3]);
        try {
            boolean transacted = batch > 0;
            Session session = connection.createSession(transacted, transacted ? Session.SESSION_TRANSACTED : Session.AUTO_ACKNOWLEDGE);
            Destination destination = "topic".equalsIgnoreCase(destinationType)
                    ? session.createTopic(destinationName) : session.createQueue(destinationName);
            MessageProducer producer = session.createProducer(destination);
            producer.setDeliveryMode(DeliveryMode.PERSISTENT);
            String template = System.getProperty("benchmark.json", "false");
            if ("true".equals(template)) {
                template = "{\"f1\":\"{message}\"}";
            }
            boolean json = !"false".equals(template) && !template.isEmpty();
            for (int i = 1; i <= messages; i++) {
                StringBuilder text = new StringBuilder("benchmark message ").append(i);
                while (text.length() < recordSize) {
                    text.append(' ');
                }
                producer.send(session.createTextMessage(json ? template.replace("{message}", text) : text.toString()));
                if (transacted && i % batch == 0) {
                    session.commit();
                }
            }
            if (transacted) {
                session.commit();
            }
            System.out.println("sent " + messages + " messages to " + destinationType + " " + destinationName);
        } finally {
            connection.close();
            context.close();
        }
    }
}
