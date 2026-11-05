# 🗺️ Start from your area

The playground is best known for its connector examples, but most of it works for any Confluent Platform or
Confluent Cloud case: brokers, transactions, clients, Control Center, Schema Registry, ksqlDB, Flink, CFK, security,
network. Pick your area: each page lists the questions you get, the command or example that answers each one, the
deep dives to read, and a support case reproduced in 3 commands.

| Area | Covers | Start here |
| --- | --- | --- |
| 🔗 Connect | self-managed and fully managed connectors, Kafka Connect | [👾 Content](/content.md), the [🧩 Connectors deep dives](/deep-dives?id=🧩-connectors) |
| 🖥️ Brokers, clients and observability | Kafka brokers, KRaft, replication, transactions, Java clients, Control Center, metrics | [🖥️ Brokers, clients and observability](/area-core-observability.md) |
| 🌊 Streams, schemas and non-Java clients | Schema Registry, data contracts, ksqlDB, Flink, Kafka Streams, .NET / JavaScript / Python / Go clients | [🌊 Streams, schemas and non-Java clients](/area-streams-schema-registry.md) |
| 🛡️ Platform, security and Cloud infra | CFK, SASL / SSL / Kerberos / LDAP / RBAC / OAuth, certificates, connectivity to Confluent Cloud | [🛡️ Platform, security and Cloud infra](/area-platform-security.md) |

> [!TIP]
> Don't know the command? Describe the symptom in your words: `playground find-command "<symptom>"` prints the 5 best
> commands with their deep dive, and `playground find-example "<words>"` the examples to start from. The full catalog
> is in [🧭 Which command do I need?](/which-command.md).

Every area uses the same workflow:

```bash
playground run -f <example or reproduction model> --tag <customer CP version> [--environment <customer security>]
# reproduce, change one thing, check again
playground repro bootstrap -f <example> -d "<case number> <short description>"   # turn it into a reproduction model
```

See [🛠 Reproduction models](/toolkit-reproduction-models.md) to share it with a colleague.
