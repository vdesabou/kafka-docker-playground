# Kafka Admin

## Objective

Quickly test [matt-mangia/kafka-admin](https://github.com/matt-mangia/kafka-admin).

## How to run

Create `$HOME/.ccloud/config`

On the host from which you are running Docker, ensure that you have properly initialized Confluent Cloud CLI and have a valid configuration file at `$HOME/.ccloud/config`.

Example:

```bash
$ cat $HOME/.ccloud/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username\="<API KEY>" password\="<API SECRET>";

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

Simply run:

```
$ ./start.sh
```

## Details of what the script is doing

Same as [Service Account and ACLs](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/ccloud-demo#service-account-and-acls), except that instead of using ccloud to create acl (ccloud kafka acl create), we use [kafka admin](https://github.com/matt-mangia/kafka-admin):

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
ccloud kafka acl list --service-account 41839
  ServiceAccountId | Permission | Operation | Resource |         Name          |  Type
+------------------+------------+-----------+----------+-----------------------+---------+
  User:41839       | ALLOW      | READ      | TOPIC    | kafka-admin-acl-topic | LITERAL
  User:41839       | ALLOW      | WRITE     | TOPIC    | kafka-admin-acl-topic | LITERAL
```

