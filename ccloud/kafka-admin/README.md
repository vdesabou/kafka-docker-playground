# Kafka Admin

## Objective

Quickly test [matt-mangia/kafka-admin](https://github.com/matt-mangia/kafka-admin).

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)
## How to run

Simply run:

```
$ ./start.sh
```

## Details of what the script is doing

Instead of using confluent CLI to create acl (confluent kafka acl create), we use [kafka admin](https://github.com/matt-mangia/kafka-admin):

```bash
java -jar ${DIR}/kafka-admin/target/kafka-admin-1.0-SNAPSHOT-jar-with-dependencies.jar -properties ${DIR}/kafka-admin.properties -config ${DIR}/config.yml -execute
```

with config.yml:

```yml
topics:
  topic:
    name: kafka-admin-acl-topic
    replication.factor: 3
    partitions: 6

acls:
  demo:
    resource-type: topic
    resource-name: kafka-admin-acl-topic
    resource-pattern: LITERAL
    principal: User:41839
    operation: READ, WRITE
    permission: ALLOW
    host: '*'
```

Output:

```

----- Topic Plan -----

increasePartitionList:

createTopicList:

Creating topics...Done!

Increasing partitions...Done!
----------------------

----- ACL Plan -----

deleteAclList:

createAclList:
(pattern=ResourcePattern(resourceType=TOPIC, name=kafka-admin-acl-topic, patternType=LITERAL), entry=(principal=User:41839, host=*, operation=READ, permissionType=ALLOW))
(pattern=ResourcePattern(resourceType=TOPIC, name=kafka-admin-acl-topic, patternType=LITERAL), entry=(principal=User:41839, host=*, operation=WRITE, permissionType=ALLOW))

Deleting ACLs...Done!

Creating ACLs...Done!
----------------------
```

ACLs are correctly applied:

```bash
confluent kafka acl list --service-account 41839
  ServiceAccountId | Permission | Operation | Resource |         Name          |  Type
+------------------+------------+-----------+----------+-----------------------+---------+
  User:41839       | ALLOW      | READ      | TOPIC    | kafka-admin-acl-topic | LITERAL
  User:41839       | ALLOW      | WRITE     | TOPIC    | kafka-admin-acl-topic | LITERAL
```

