# Getting Started with Service Bus Queues

This sample shows the essential API elements for interacting with messages and a
Service Bus Queue.

You will learn how to establish a connection, and to send and receive messages,
and you will learn about the most important properties of Service Bus messages.

Refer to the main [README](../README.md) document for setup instructions. 

## Sample Code 

The sample is documented inline in the [QueuesGettingStarted.java](./src/main/java/com/microsoft/azure/servicebus/samples/queuesgettingstarted/QueuesGettingStarted.java) file.

To keep things reasonably simple, the sample program keeps message sender and
message receiver code within a single hosting application, even though these
roles are often spread across applications, services, or at least across
independently deployed and run tiers of applications or services. For clarity,
the send and receive activities are kept as separate as if they were different
apps and share no API object instances.

