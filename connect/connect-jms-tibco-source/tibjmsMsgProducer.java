/*
 * Copyright (c) 2002-2016 TIBCO Software Inc.
 * All Rights Reserved. Confidential & Proprietary.
 * For more information, please contact:
 * TIBCO Software Inc., Palo Alto, California, USA
 *
 * $Id: tibjmsMsgProducer.java 90180 2016-12-13 23:00:37Z $
 *
 */

/*
 * This is a simple sample of a basic tibjmsMsgProducer.
 *
 * This sample publishes specified message(s) on a specified
 * destination and quits.
 *
 * Notice that the specified destination should exist in your configuration
 * or your topics/queues configuration file should allow
 * creation of the specified topic or queue. Sample configuration supplied with
 * the TIBCO Enterprise Message Service distribution allows creation of any
 * destination.
 *
 * If this sample is used to publish messages into
 * tibjmsMsgConsumer sample, the tibjmsMsgConsumer
 * sample must be started first.
 *
 * If -topic is not specified this sample will use a topic named
 * "topic.sample".
 *
 * Usage:  java tibjmsMsgProducer  [options]
 *                               <message-text1>
 *                               ...
 *                               <message-textN>
 *
 *  where options are:
 *
 *   -server    <server-url>  Server URL.
 *                            If not specified this sample assumes a
 *                            serverUrl of "tcp://localhost:7222"
 *   -user      <user-name>   User name. Default is null.
 *   -password  <password>    User password. Default is null.
 *   -topic     <topic-name>  Topic name. Default value is "topic.sample"
 *   -queue     <queue-name>  Queue name. No default
 *
 */

import java.util.*;
import javax.jms.*;

public class tibjmsMsgProducer
{
    /*-----------------------------------------------------------------------
     * Parameters
     *----------------------------------------------------------------------*/

    String          serverUrl    = null;
    String          userName     = null;
    String          password     = null;
    String          name         = "topic.sample";
    Vector<String>  data         = new Vector<String>();
    boolean         useTopic     = true;
    boolean         useAsync     = false;

    /*-----------------------------------------------------------------------
     * Variables
     *----------------------------------------------------------------------*/
    Connection      connection   = null;
    Session         session      = null;
    MessageProducer msgProducer  = null;
    Destination     destination  = null;

    TibjmsCompletionListener completionListener = null;

    class TibjmsCompletionListener implements CompletionListener
    {
        // Note:  Use caution when modifying a message in a completion
        // listener to avoid concurrent message use.

        public void onCompletion(Message msg)
        {
            try
            {
                System.err.printf("Successfully sent message %s.\n",
                    ((TextMessage)msg).getText());
            }
            catch (JMSException e)
            {
                System.err.println("Error retrieving message text.");
                e.printStackTrace(System.err);
            }
        }

        public void onException(Message msg, Exception ex)
        {
            try
            {
                System.err.printf("Error sending message %s.\n",
                        ((TextMessage)msg).getText());
            }
            catch (JMSException e)
            {
                System.err.println("Error retrieving message text.");
                e.printStackTrace(System.err);
            }

            ex.printStackTrace(System.err);
        }

    }

    public tibjmsMsgProducer(String[] args)
    {
        parseArgs(args);

        try
        {
            tibjmsUtilities.initSSLParams(serverUrl,args);
        }
        catch (JMSSecurityException e)
        {
            System.err.println("JMSSecurityException: "+e.getMessage()+", provider="+e.getErrorCode());
            e.printStackTrace();
            System.exit(0);
        }

        /* print parameters */
        System.err.println("\n------------------------------------------------------------------------");
        System.err.println("tibjmsMsgProducer SAMPLE");
        System.err.println("------------------------------------------------------------------------");
        System.err.println("Server....................... "+((serverUrl != null)?serverUrl:"localhost"));
        System.err.println("User......................... "+((userName != null)?userName:"(null)"));
        System.err.println("Destination.................. "+name);
        System.err.println("Send Asynchronously.......... "+useAsync);
        System.err.println("Message Text................. ");
        for (int i=0;i<data.size();i++)
        {
            System.err.println(data.elementAt(i));
        }
        System.err.println("------------------------------------------------------------------------\n");

        try
        {
            TextMessage msg;
            int         i;

            if (data.size() == 0)
            {
                System.err.println("***Error: must specify at least one message text\n");
                usage();
            }

            System.err.println("Publishing to destination '"+name+"'\n");

            ConnectionFactory factory = new com.tibco.tibjms.TibjmsConnectionFactory(serverUrl);

            connection = factory.createConnection(userName,password);

            /* create the session */
            session = connection.createSession(javax.jms.Session.AUTO_ACKNOWLEDGE);

            /* create the destination */
            if (useTopic)
                destination = session.createTopic(name);
            else
                destination = session.createQueue(name);

            /* create the producer */
            msgProducer = session.createProducer(null);

            if (useAsync)
                completionListener = new TibjmsCompletionListener();

            /* publish messages */
            for (i = 0; i<data.size(); i++)
            {
                /* create text message */
                msg = session.createTextMessage();

                /* set header titi with value toto */
                msg.setStringProperty("titi","toto");

                /* set message text */
                msg.setText(data.elementAt(i));

                /* publish message */
                if (useAsync == false)
                    msgProducer.send(destination, msg);
                else
                    msgProducer.send(destination, msg, completionListener);

                System.err.println("Published message: "+data.elementAt(i));
            }

            /* close the connection */
            connection.close();
        }
        catch (JMSException e)
        {
            e.printStackTrace();
            System.exit(-1);
        }
    }

    /*-----------------------------------------------------------------------
    * usage
    *----------------------------------------------------------------------*/
    private void usage()
    {
        System.err.println("\nUsage: java tibjmsMsgProducer [options] [ssl options]");
        System.err.println("                                <message-text-1>");
        System.err.println("                                [<message-text-2>] ...");
        System.err.println("\n");
        System.err.println("   where options are:");
        System.err.println("");
        System.err.println("   -server   <server URL>  - EMS server URL, default is local server");
        System.err.println("   -user     <user name>   - user name, default is null");
        System.err.println("   -password <password>    - password, default is null");
        System.err.println("   -topic    <topic-name>  - topic name, default is \"topic.sample\"");
        System.err.println("   -queue    <queue-name>  - queue name, no default");
        System.err.println("   -async                  - send asynchronously, default is false");
        System.err.println("   -help-ssl               - help on ssl parameters");
        System.exit(0);
    }

    /*-----------------------------------------------------------------------
     * parseArgs
     *----------------------------------------------------------------------*/
    void parseArgs(String[] args)
    {
        int i=0;

        while (i < args.length)
        {
            if (args[i].compareTo("-server")==0)
            {
                if ((i+1) >= args.length) usage();
                serverUrl = args[i+1];
                i += 2;
            }
            else
            if (args[i].compareTo("-topic")==0)
            {
                if ((i+1) >= args.length) usage();
                name = args[i+1];
                i += 2;
            }
            else
            if (args[i].compareTo("-queue")==0)
            {
                if ((i+1) >= args.length) usage();
                name = args[i+1];
                i += 2;
                useTopic = false;
            }
            else
            if (args[i].compareTo("-async")==0)
            {
                i += 1;
                useAsync = true;
            }
            else
            if (args[i].compareTo("-user")==0)
            {
                if ((i+1) >= args.length) usage();
                userName = args[i+1];
                i += 2;
            }
            else
            if (args[i].compareTo("-password")==0)
            {
                if ((i+1) >= args.length) usage();
                password = args[i+1];
                i += 2;
            }
            else
            if (args[i].compareTo("-help")==0)
            {
                usage();
            }
            else
            if (args[i].compareTo("-help-ssl")==0)
            {
                tibjmsUtilities.sslUsage();
            }
            else
            if (args[i].startsWith("-ssl"))
            {
                i += 2;
            }
            else
            {
                data.addElement(args[i]);
                i++;
            }
        }
    }

    /*-----------------------------------------------------------------------
     * main
     *----------------------------------------------------------------------*/
    public static void main(String[] args)
    {
        tibjmsMsgProducer t = new tibjmsMsgProducer(args);
    }
}

