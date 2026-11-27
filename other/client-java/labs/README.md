# Single-file Java programs

Small teaching programs for the Java producer and consumer. Each one is a single `.java` file that the JDK runs straight from source (`java X.java`, Java 11 and later), with no build step. They run in the `client-java` container started by [`start-lab.sh`](../start-lab.sh), where this folder is mounted in `/app/labs` (the working directory) and the client jars are in `$CONFLUENT_HOME/share/java/kafka`:

```bash
playground container exec -c client-java --command "java -cp \"\$CONFLUENT_HOME/share/java/kafka/*\" ProducerBasics.java broker:9092"
```

The producer programs write to topic `orders` (create it first, with 3 partitions for `PartitionerDemo.java`). The bootstrap servers argument is optional: without it the programs use `localhost:9092,localhost:9094,localhost:9096`, a three-broker cluster on the local host.

| Program | What it shows | Arguments |
| --- | --- | --- |
| `ProducerBasics.java` | sends 5 keyed records with a header, prints the partition and offset of each from the callback | `[bootstrap servers]` |
| `SyncVsAsync.java` | 2000 records with `send().get()` each time, then 2000 with `send()` and a callback, and the time of each | `[bootstrap servers]` |
| `PartitionerDemo.java` | a custom `Partitioner`: keys starting with `vip-` go to partition 0, the others are hashed over the other partitions | `[bootstrap servers]` |
| `MaxBlockDemo.java` | `max.block.ms=5000`: how long `send()` blocks when the topic or the cluster is not available | `<topic> [bootstrap servers]` |
| `ShowDefaults.java` | the producer defaults of the client version, worked out by `ProducerConfig` without connecting | none |
| `Defaults.java` | the same for a longer list of producer settings | none |
| `LabConsumer.java` | a configurable consumer: rebalance listener, commit mode, slow processing, poison record handling. `key=value` arguments, keys starting with `x.` drive the program (`x.topic`, `x.run.ms`, `x.sleep.ms`, `x.commit`, `x.print`...), the others go to the consumer configuration | `bootstrap.servers=broker:9092 group.id=<group> [key=value...]` |

`LabConsumer.java` stops on its own after `x.run.ms` (30 seconds by default).

The client jars log through log4j2, like in the Confluent Platform 8 images (`log4j-slf4j2-impl` in the image, no other SLF4J binding). Without a configuration, log4j2 prints errors only. [`log4j2.xml`](log4j2.xml) prints INFO to stderr without the client configuration dumps; pass it, or your own file (for example with `org.apache.kafka.clients.consumer` at `DEBUG`), with `-Dlog4j2.configurationFile`:

```bash
playground container exec -c client-java --command "java -Dlog4j2.configurationFile=log4j2.xml -cp \"\$CONFLUENT_HOME/share/java/kafka/*\" LabConsumer.java bootstrap.servers=broker:9092 group.id=my-group"
```

`ps` and `pkill` are available in the container, for example to pause and resume a consumer started with `client.id=paused`:

```bash
playground container exec -c client-java --command "pkill -STOP -f client.id=paused"
playground container exec -c client-java --command "pkill -CONT -f client.id=paused"
```
