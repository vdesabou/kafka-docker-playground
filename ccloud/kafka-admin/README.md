# Kafka Admin

## Objective

Quickly test [matt-mangia/kafka-admin](https://github.com/matt-mangia/kafka-admin).

## Prerequisites

* Properly initialized Confluent Cloud CLI

You must be already logged in with confluent CLI which needs to be setup with correct environment, cluster and api key to use:

Typical commands to run:

```bash
$ confluent login --save

Use environment $ENVIRONMENT_ID:
$ confluent environment use $ENVIRONMENT_ID

Use cluster $CLUSTER_ID:
$ confluent kafka cluster use $CLUSTER_ID

Store api key $API_KEY:
$ confluent api-key store $API_KEY $API_SECRET --resource $CLUSTER_ID --force

Use api key $API_KEY:
$ confluent api-key use $API_KEY --resource $CLUSTER_ID
```

* Create a file `$HOME/.confluent/config`

You should have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";

// Schema Registry specific settings
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR_API_KEY>:<SR_API_SECRET>
schema.registry.url=<SR ENDPOINT>

// license
confluent.license=<YOUR LICENSE>

// ccloud login password
ccloud.user=<ccloud login>
ccloud.password=<ccloud password>
```
## How to run

Simply run:

```
$ ./start.sh
```

## Details of what the script is doing

Same as [Service Account and ACLs](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/ccloud-demo#service-account-and-acls), except that instead of using confluent CLI to create acl (confluent kafka acl create), we use [kafka admin](https://github.com/matt-mangia/kafka-admin):

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

