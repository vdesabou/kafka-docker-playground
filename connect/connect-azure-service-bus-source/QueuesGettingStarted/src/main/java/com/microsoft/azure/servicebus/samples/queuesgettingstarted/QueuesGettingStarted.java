// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

package com.microsoft.azure.servicebus.samples.queuesgettingstarted;

import com.azure.messaging.servicebus.*;
import com.google.gson.Gson;

import java.time.Duration;
import java.util.*;
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

    public void run(String connectionString) throws Exception {

        String queueName = System.getenv("AZURE_SERVICE_BUS_QUEUE_NAME");

        // Create a ServiceBusSenderClient for sending messages
        ServiceBusSenderClient senderClient = new ServiceBusClientBuilder()
            .connectionString(connectionString)
            .sender()
            .queueName(queueName)
            .buildClient();

        // Send messages synchronously
        for (int i = 0; i < scientists.length; i++) {
            ServiceBusMessage message = new ServiceBusMessage(GSON.toJson(scientists[i]));
            message.setMessageId(Integer.toString(i));
            message.setContentType("application/json");
            message.setSubject("Scientist");
            message.setTimeToLive(Duration.ofMinutes(2));

            System.out.printf("\nMessage sending: Id = %s", message.getMessageId());

            try {
                senderClient.sendMessage(message);
                System.out.printf("\n\tMessage acknowledged: Id = %s", message.getMessageId());
            } catch (Exception e) {
                System.out.printf("\n\tFailed to send message: Id = %s, Error = %s",
                                message.getMessageId(), e.getMessage());
            }
        }

        // Close the sender
        senderClient.close();
        System.out.println("\nAll messages sent and client closed successfully.");
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
}
