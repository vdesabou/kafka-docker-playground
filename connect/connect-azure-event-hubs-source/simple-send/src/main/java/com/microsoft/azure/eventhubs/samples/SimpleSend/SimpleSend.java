/*
 * Copyright (c) Microsoft. All rights reserved.
 * Licensed under the MIT license. See LICENSE file in the project root for full license information.
 */
package com.microsoft.azure.eventhubs.samples.SimpleSend;

import com.azure.messaging.eventhubs.*;
import com.azure.messaging.eventhubs.models.CreateBatchOptions;

import java.util.Arrays;
import java.util.List;

public class SimpleSend {

    private static final String connectionString = System.getenv("AZURE_EVENT_CONNECTION_STRING");
    private static final String eventHubName = System.getenv("AZURE_EVENT_HUBS_NAME");

    public static void main(String[] args) {
        publishEvents();
    }

    /**
     * Code sample for publishing events.
     * 
     * @throws IllegalArgumentException if the EventData is bigger than the max
     *                                  batch size.
     */
    public static void publishEvents() {
        // create a producer client
        EventHubProducerClient producer = new EventHubClientBuilder().connectionString(connectionString, eventHubName)
                .buildProducerClient();

        // sample events in an array
        List<EventData> allEvents = Arrays.asList(new EventData("Foo"), new EventData("Bar"));

        final CreateBatchOptions options = new CreateBatchOptions().setPartitionKey("mykey");
        
        // create a batch
        EventDataBatch eventDataBatch = producer.createBatch(options);
        
        for (EventData eventData : allEvents) {
            // try to add the event from the array to the batch
            if (!eventDataBatch.tryAdd(eventData)) {
                // if the batch is full, send it and then create a new batch
                producer.send(eventDataBatch);
                eventDataBatch = producer.createBatch();

                // Try to add that event that couldn't fit before.
                if (!eventDataBatch.tryAdd(eventData)) {
                    throw new IllegalArgumentException(
                            "Event is too large for an empty batch. Max size: " + eventDataBatch.getMaxSizeInBytes());
                }
            }
        }
        // send the last batch of remaining events
        if (eventDataBatch.getCount() > 0) {
            producer.send(eventDataBatch);
        }
        producer.close();
    }
}
