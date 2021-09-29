package com.sample.jms.toolkit;

import java.util.Hashtable;
import javax.jms.*;
import javax.naming.Context;
import javax.naming.InitialContext;
import javax.naming.NamingException;

public class JMSReceiver implements MessageListener {
    // Defines the JNDI context factory.
    public final static String JNDI_FACTORY = "weblogic.jndi.WLInitialContextFactory";
    // Defines the JMS connection factory for the queue.
    public final static String JMS_FACTORY = "jms/TestConnectionFactory";

    public final static String URL = "t3://weblogic-jms:7001";

    // Defines the queue.
    public final static String QUEUE = "myQueue";
    private QueueConnectionFactory qconFactory;
    private QueueConnection qcon;
    private QueueSession qsession;
    private QueueReceiver qreceiver;
    private Queue queue;
    private boolean quit = false;
    /**
     * Message listener interface.
     * @param msg  message
     */
    public void onMessage(Message msg) {
        try {
            String msgText;
            if (msg instanceof TextMessage) {
                msgText = ((TextMessage) msg).getText();
            } else {
                msgText = msg.toString();
            }
            System.out.println("Message Received: " + msgText);
            if (msgText.equalsIgnoreCase("This is my message")) {
                synchronized(this) {
                    quit = true;
                    this.notifyAll(); // Notify main thread to quit
                }
            }
        } catch (JMSException jmse) {
            System.err.println("An exception occurred: " + jmse.getMessage());
        }
    }
    /**
     * Creates all the necessary objects for receiving
     * messages from a JMS queue.
     *
     * @param   ctx    JNDI initial context
     * @param    queueName    name of queue
     * @exception NamingException if operation cannot be performed
     * @exception JMSException if JMS fails to initialize due to internal error
     */
    public void init(Context ctx, String queueName)
    throws NamingException, JMSException {
        qconFactory = (QueueConnectionFactory) ctx.lookup("myFactory");
        qcon = qconFactory.createQueueConnection();
        qsession = qcon.createQueueSession(false, Session.AUTO_ACKNOWLEDGE);
        queue = (Queue) ctx.lookup(queueName);
        qreceiver = qsession.createReceiver(queue);
        qreceiver.setMessageListener(this);
        qcon.start();
    }
    /**
     * Closes JMS objects.
     * @exception JMSException if JMS fails to close objects due to internal error
     */
    public void close() throws JMSException {
        qreceiver.close();
        qsession.close();
        qcon.close();
    }
    /**
     * main() method.
     *
     * @param args  WebLogic Server URL
     * @exception  Exception if execution fails
     */
    public static void main(String[] args) throws Exception {
        InitialContext ic = getInitialContext();
        JMSReceiver qr = new JMSReceiver();
        qr.init(ic, QUEUE);
        System.out.println(
            "JMS Ready To Receive Messages...");
        // Wait until a "This is my message" message has been received.
        synchronized(qr) {
            while (!qr.quit) {
                try {
                    qr.wait();
                } catch (InterruptedException ie) {}
            }
        }
        qr.close();
    }
    private static InitialContext getInitialContext() throws NamingException {
        Hashtable env = new Hashtable();
        env.put(Context.INITIAL_CONTEXT_FACTORY, JNDI_FACTORY);
        env.put(Context.PROVIDER_URL, URL);
        return new InitialContext(env);
    }
}