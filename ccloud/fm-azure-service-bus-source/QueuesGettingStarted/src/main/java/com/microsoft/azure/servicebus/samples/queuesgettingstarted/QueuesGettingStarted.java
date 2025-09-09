// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

package com.microsoft.azure.servicebus.samples.queuesgettingstarted;

import com.google.gson.reflect.TypeToken;
import com.azure.messaging.servicebus.*;
import com.google.gson.Gson;

import static java.nio.charset.StandardCharsets.*;

import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Function;

import org.apache.commons.cli.*;

public class QueuesGettingStarted {

    static final Gson GSON = new Gson();
    
    // Scientists data
    private final Map<String, String>[] scientists = new Map[]{
        Map.of("name", "Einstein", "firstName", "Albert"),
        Map.of("name", "Heisenberg", "firstName", "Werner"),
        Map.of("name", "Curie", "firstName", "Marie"),
        Map.of("name", "Hawking", "firstName", "Steven"),
        Map.of("name", "Newton", "firstName", "Isaac"),
        Map.of("name", "Bohr", "firstName", "Niels"),
        Map.of("name", "Faraday", "firstName", "Michael"),
        Map.of("name", "Galilei", "firstName", "Galileo"),
        Map.of("name", "Kepler", "firstName", "Johannes"),
        Map.of("name", "Kopernikus", "firstName", "Nikolaus")
    };
    
    private final int totalSend = scientists.length;

    public void run(String connectionString) throws Exception {

        String queueName = System.getenv("AZURE_SERVICE_BUS_QUEUE_NAME");
        
        // Create a ServiceBusProcessorClient for receiving messages
        ServiceBusProcessorClient processorClient = new ServiceBusClientBuilder()
            .connectionString(connectionString)
            .processor()
            .queueName(queueName)
            .processMessage(this::processMessage)
            .processError(this::processError)
            .buildProcessorClient();

        // Start the processor
        processorClient.start();

        // Create a ServiceBusSenderClient for sending messages
        ServiceBusSenderClient senderClient = new ServiceBusClientBuilder()
            .connectionString(connectionString)
            .sender()
            .queueName(queueName)
            .buildClient();

        // Send messages
        this.sendMessages(senderClient).join(); // Wait for all send operations to complete
        
        // Close the sender
        senderClient.close();

        // wait for ENTER or 10 seconds elapsing
        waitForEnter(10);

        // shut down processor
        processorClient.close();
    }

    // Message processing method for the new SDK
    public void processMessage(ServiceBusReceivedMessageContext context) {
        ServiceBusReceivedMessage message = context.getMessage();
        try {
            if (message.getSubject() != null &&
                message.getContentType() != null &&
                message.getSubject().contentEquals("Scientist") &&
                message.getContentType().contentEquals("application/json")) {
                
                Map<String, Object> scientist = GSON.fromJson(new String(message.getBody().toBytes(), UTF_8), Map.class);
                System.out.printf(
                    "\n\tMessage received:\n\tMessageId = %s,\n\tBody = %s,\n\tScientist Name = %s,\n",
                    message.getMessageId(),
                    new String(message.getBody().toBytes(), UTF_8),
                    scientist.get("name")
                );
            }
            // Complete the message
            context.complete();
        } catch (Exception e) {
            // Abandon the message if processing fails
            context.abandon();
            System.out.printf("Failed to process message: %s", e.getMessage());
        }
    }

    // Error processing method for the new SDK
    public void processError(ServiceBusErrorContext context) {
        System.out.printf("Error in processor: %s - %s%n", 
                          context.getErrorSource(), 
                          context.getException().getMessage());
    }

    CompletableFuture<Void> sendMessages(ServiceBusSenderClient senderClient) {
        List<CompletableFuture<Void>> tasks = new ArrayList<>();
        for (int i = 0; i < totalSend; i++) {
            // Create message
            ServiceBusMessage message = new ServiceBusMessage(GSON.toJson(scientists[i]));
            message.setMessageId(Integer.toString(i));
            message.setContentType("application/json");
            message.setSubject("Scientist");
            message.setTimeToLive(Duration.ofMinutes(2));

            System.out.printf("\nMessage sending: Id = %s", message.getMessageId());
            
            // Send message synchronously to avoid race conditions
            try {
                senderClient.sendMessage(message);
                System.out.printf("\n\tMessage acknowledged: Id = %s", message.getMessageId());
            } catch (Exception e) {
                System.out.printf("\n\tFailed to send message: Id = %s, Error = %s", 
                                message.getMessageId(), e.getMessage());
            }
        }
        return CompletableFuture.completedFuture(null);
    }

    public static void main(String[] args) {

        System.exit(runApp(args, (connectionString) -> {
            QueuesGettingStarted app = new QueuesGettingStarted();
            try {
                app.run(connectionString);
                return 0;
            } catch (Exception e) {
                System.out.printf("%s", e.toString());
                return 1;
            }
        }));
    }

    static final String SB_SAMPLES_CONNECTIONSTRING = "SB_SAMPLES_CONNECTIONSTRING";

    public static int runApp(String[] args, Function<String, Integer> run) {
        try {

            String connectionString = null;

            // parse connection string from command line
            Options options = new Options();
            options.addOption(new Option("c", true, "Connection string"));
            CommandLineParser clp = new DefaultParser();
            CommandLine cl = clp.parse(options, args);
            if (cl.getOptionValue("c") != null) {
                connectionString = cl.getOptionValue("c");
            }

            // get overrides from the environment
            String env = System.getenv(SB_SAMPLES_CONNECTIONSTRING);
            if (env != null) {
                connectionString = env;
            }

            if (connectionString == null) {
                HelpFormatter formatter = new HelpFormatter();
                formatter.printHelp("run jar with", "", options, "", true);
                return 2;
            }
            return run.apply(connectionString);
        } catch (Exception e) {
            System.out.printf("%s", e.toString());
            return 3;
        }
    }

    private void waitForEnter(int seconds) {
        ExecutorService executor = Executors.newCachedThreadPool();
        try {
            executor.invokeAny(Arrays.asList(() -> {
                System.in.read();
                return 0;
            }, () -> {
                Thread.sleep(seconds * 1000);
                return 0;
            }));
        } catch (Exception e) {
            // absorb
        }
    }
}
