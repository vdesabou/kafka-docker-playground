package com.sample.jms.toolkit;

import java.util.Hashtable;
import javax.jms.Connection;
import javax.jms.ConnectionFactory;
import javax.jms.JMSException;
import javax.jms.Message;
import javax.jms.MessageProducer;
import javax.jms.Queue;
import javax.jms.QueueSession;
import javax.jms.Session;
import javax.naming.Context;
import javax.naming.InitialContext;
import javax.naming.NamingException;

public class JMSSender {
	public final static String JNDI_FACTORY = "weblogic.jndi.WLInitialContextFactory";

	public final static String URL = "t3://weblogic-jms:7001";

	public static void main(String[] args) throws NamingException, JMSException {
		System.out.println("Hello World!");

		Connection connection = null;
		try {
			System.out.println("Create JNDI Context");
			Context context = getInitialContext();

			System.out.println("Get connection facory");
			ConnectionFactory connectionFactory = (ConnectionFactory) context.lookup("myFactory");

			System.out.println("Create connection");
			connection = connectionFactory.createConnection();

			System.out.println("Create session");
			Session session = connection.createSession(false, QueueSession.AUTO_ACKNOWLEDGE);

			System.out.println("Lookup queue");
			Queue queue = (Queue) context.lookup("myQueue");

			System.out.println("Start connection");
			connection.start();

			System.out.println("Create producer");
			MessageProducer producer = session.createProducer(queue);

			System.out.println("Create hello world message");
			Message hellowWorldText = session.createTextMessage("Hello World!");

			System.out.println("Send hello world message");

			producer.send(hellowWorldText);
		} finally {
			if (connection != null) {
				System.out.println("close the connection");
				connection.close();
			}
		}
	}

	private static InitialContext getInitialContext() throws NamingException {
		Hashtable env = new Hashtable();
		env.put(Context.INITIAL_CONTEXT_FACTORY, JNDI_FACTORY);
		env.put(Context.PROVIDER_URL, URL);
		return new InitialContext(env);
	}
}