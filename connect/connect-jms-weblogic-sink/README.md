# Oracle Weblogic Sink with JMS connector

## Objective

Quickly test the [JMS Sink](https://docs.confluent.io/kafka-connectors/jms-sink/current/overview.html) connector with an Oracle WebLogic JMS queue.

## Prerequisites

The example uses the Oracle WebLogic Server (Developer Tier, version `12.2.1.3`) docker [image](https://container-registry.oracle.com). You need to register and acknowledge the license terms and conditions to get the image:

![image](screenshot3.jpg)

If image `container-registry.oracle.com/middleware/weblogic:12.2.1.3` is not present locally, the script pulls it using:

| Variable | Description |
| --- | --- |
| `ORACLE_CONTAINER_REGISTRY_USERNAME` | Oracle account used to sign in to the Oracle Container Registry |
| `ORACLE_CONTAINER_REGISTRY_PASSWORD` | Oracle Container Registry auth token |

To get `ORACLE_CONTAINER_REGISTRY_PASSWORD` (see [Oracle documentation](https://docs.oracle.com/en/operating-systems/oracle-linux/podman/podman-UsingContainerRegistries.html#generating-an-authentication-key-for-use-with-oracle-container-registry)):

* In a web browser, sign in to the Oracle Container Registry using an Oracle account at https://container-registry.oracle.com.
* Select the profile name, and in the profile menu that appears select **Auth Token**.
* Select **Generate Secret Key** and note down the secret key. This is only displayed once, during the initial generation.

With CP 8.x, the minimum supported connector version is 2.1.16 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-weblogic-sink.sh
```

The WebLogic console is reachable at [http://127.0.0.1:7001/console](http://127.0.0.1:7001/console) (`weblogic`/`welcome1`). You can use it to see all JMS resources:

![console](screenshot1.jpg)

## What the script does

1. Builds the `weblogic-jms:latest` image with a JMS server, connection factory `myFactory` and distributed queue `MyDistributedQueue` (first run only).
2. Extracts `weblogic.jar` and `wlthint3client.jar` from the image, builds the `jms-receiver` Java client, and copies `wlthint3client.jar` into the `confluentinc-kafka-connect-jms-sink` plugin `lib` folder.
3. Starts the environment and waits for WebLogic to be ready.
4. Produces one message to topic `sink-messages` with `playground topic produce`.
5. Creates the JMS sink connector `weblogic-topic-sink` (`weblogic.jndi.WLInitialContextFactory`, `t3://weblogic-jms:7001`, destination `myJMSServer/mySystemModule!myJMSServer@MyDistributedQueue`).
6. Verifies that the message is received in the queue, using the `jms-receiver` client.
