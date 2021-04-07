package com.sample.jms.toolkit;

import java.util.Hashtable;

import javax.jms.JMSException;
import javax.jms.Message;
import javax.jms.Queue;
import javax.jms.QueueConnection;
import javax.jms.QueueConnectionFactory;
import javax.jms.QueueSender;
import javax.jms.QueueSession;
import javax.jms.Session;
import javax.naming.Context;
import javax.naming.InitialContext;
import javax.naming.NamingException;

public class JMSSender {

	public static void main(String[] args) throws NamingException, JMSException {

		String JNDIFactory = "weblogic.jndi.WLInitialContextFactory";
		String providerUrl = "t3://weblogic-jms:7001";
		Hashtable<String, String> env = new Hashtable<String, String>();
		env.put(Context.INITIAL_CONTEXT_FACTORY, JNDIFactory);
		env.put(Context.PROVIDER_URL, providerUrl);
		Context ctx = new InitialContext(env);

		QueueConnectionFactory connFactory = (QueueConnectionFactory) ctx.lookup("weblogic.jms.ConnectionFactory");
		QueueConnection qConn = (QueueConnection) connFactory.createConnection("weblogic","welcome1");
		QueueSession qSession = qConn.createQueueSession(false, Session.AUTO_ACKNOWLEDGE);
		Queue queue = (Queue) ctx.lookup("myJMSServer/mySystemModule!myDistributedQueue");
		QueueSender qSender = qSession.createSender(queue);
		// 100b
		Message msg = qSession.createTextMessage("helloworldhelloworldhelloworldhelloworldhelloworldhelloworldhelloworldhelloworldhelloworldhelloworld");
		// 10000x100b=1m
		// 100000x100b=10m
		for (int i = 1; i <= 100; i++) {
			System.out.println(i);
			qSender.send(msg);
		}

		qSender.close();
		qSession.close();
		qConn.close();

	}
}