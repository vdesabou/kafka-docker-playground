# Cluster Linking Quick Start with service account only

This is the [quickstart](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/quickstart.html) that is being followed here, but with requirement to use only service accounts (least privileges principle).

⚠️ This is not an automated test, just some notes of the tests done.

- [Cluster Linking Quick Start with service account only](#cluster-linking-quick-start-with-service-account-only)
  - [Create source and destination clusters](#create-source-and-destination-clusters)
  - [Create service accounts and API keys](#create-service-accounts-and-api-keys)
    - [Source cluster](#source-cluster)
    - [Destination cluster](#destination-cluster)
  - [Creating Cluster Link](#creating-cluster-link)
    - [Testing cluster linking without ACLs set:](#testing-cluster-linking-without-acls-set)
      - [Attempt to use confluent kafka link create](#attempt-to-use-confluent-kafka-link-create)
      - [Using kafka-cluster-links (working)](#using-kafka-cluster-links-working)
    - [Setting up ACLs](#setting-up-acls)
    - [Creating or modifying a cluster link](#creating-or-modifying-a-cluster-link)
  - [Create source topic and populate it](#create-source-topic-and-populate-it)
  - [Create mirror topic on destination without ACLs](#create-mirror-topic-on-destination-without-acls)
    - [Permissions for the cluster link to read from the source cluster](#permissions-for-the-cluster-link-to-read-from-the-source-cluster)
    - [Create mirror topic after ACLs are set](#create-mirror-topic-after-acls-are-set)
- [✅ Verifications](#-verifications)
  - [Consumer offsets](#consumer-offsets)
  - [Update topic config](#update-topic-config)
  - [ACLs sync](#acls-sync)
  - [Deleting user account that created link and mirror topic](#deleting-user-account-that-created-link-and-mirror-topic)

## Create source and destination clusters

```bash
confluent kafka cluster create VincentClusterLinkingSource --type basic --cloud aws --region us-west-2
```

```bash
confluent kafka cluster create VincentClusterLinkingDestination --type dedicated --cloud aws --region us-east-1 --cku 1 --availability single-zone
```

```
source_id=lkc-73zw1
source_endpoint=pkc-pgq85.us-west-2.aws.confluent.cloud:9092
destination_id=lkc-p80ym
destination_endpoint=pkc-3n1v0.us-east-1.aws.confluent.cloud:9092
```

## Create service accounts and API keys

### Source cluster

```bash
confluent iam service-account create SA-Source-ClusterLinking --description "SA for Source cluster" 

+-------------+-----------------------+
| ID          | sa-12nn2j             |
| Name        | SA-Source-ClusterLinking     |
| Description | SA for Source cluster |
+-------------+-----------------------+
```

source_service_account=sa-12nn2j

```bash
confluent api-key create --resource $source_id --service-account $source_service_account --description "api key for SA-ClusterLinking"
It may take a couple of minutes for the API key to be ready.
Save the API key and secret. The secret is not retrievable later.
+---------+------------------------------------------------------------------+
| API Key | <SOURCE_SA_API_KEY>                                                 |
| Secret  | <SOURCE_SA_API_SECRET> |
+---------+------------------------------------------------------------------+
```

source_api_key="<SOURCE_SA_API_KEY>"
source_api_secret="<SOURCE_SA_API_SECRET>"

### Destination cluster

```bash
confluent iam service-account create SA--Destination-ClusterLinking --description "SA for Destination cluster" 
+-------------+--------------------------------+
| ID          | sa-do11o7                      |
| Name        | SA--Destination-ClusterLinking |
| Description | SA for Destination cluster     |
+-------------+--------------------------------+
```

destination_service_account=sa-do11o7

```bash
confluent api-key create --resource $destination_id --service-account $destination_service_account --description "api key for SA-ClusterLinking"
It may take a couple of minutes for the API key to be ready.
Save the API key and secret. The secret is not retrievable later.
+---------+------------------------------------------------------------------+
| API Key | <DESTINATION_SA_API_KEY>                                                 |
| Secret  | <DESTINATION_SA_API_SECRET> |
+---------+------------------------------------------------------------------+
```

destination_api_key="<DESTINATION_SA_API_KEY>"
destination_api_secret="<DESTINATION_SA_API_SECRET>"

## Creating Cluster Link

### Testing cluster linking without ACLs set:

#### Attempt to use confluent kafka link create

Setup CLI to use destination cluster

```bash
confluent kafka cluster use $destination_id
Set Kafka cluster "lkc-p80ym" as the active cluster for environment "t36311".
```

Setup CLI to use destination api key

```bash
confluent api-key use $destination_api_key --resource $destination_id
Set API Key "<DESTINATION_SA_API_KEY>" as the active API key for "lkc-p80ym".
```

```bash
confluent kafka link create my-link --cluster $destination_id \
    --source-cluster-id $source_id \
    --source-bootstrap-server $source_endpoint \
    --source-api-key "$source_api_key" --source-api-secret "$source_api_secret"
```

It works because User with `OrgAdmin` is used here. 

**FIXTHIS**: is there any way to specify that we want to use service account for destination cluster ?? Slack discussion [here](https://confluent.slack.com/archives/C01LNM9C8S2/p1638373082429100)

Trying with context:

```bash
 confluent context create destination-using-sa-context --bootstrap $destination_endpoint --api-key $destination_api_key --api-secret $destination_api_secret 
+------------+----------------------------------------------+
| Name       | destination-using-sa-context                 |
| Platform   | pkc-3n1v0.us-east-1.aws.confluent.cloud:9092 |
| Credential | api-key-<DESTINATION_SA_API_KEY>                     |
+------------+----------------------------------------------+
```

```bash
confluent kafka link create my-link-with-confluent-cli --cluster $destination_id \
    --source-cluster-id $source_id \
    --source-bootstrap-server $source_endpoint \
    --source-api-key "$source_api_key" --source-api-secret "$source_api_secret" \
    --context destination-using-sa-context
```

Getting:

```
Error: Kafka cluster not found or access forbidden: Kafka cluster not found or access forbidden: error describing kafka cluster: Forbidden Access
```

#### Using kafka-cluster-links (working)

So it seems to be required to use `kafka-cluster-links` instead:

```bash
kafka-cluster-links --create --link my-link \
  --cluster-id $source_id \
  --config-file source.config \
  --bootstrap-server $destination_endpoint \
  --command-config destination.config
```

where `destination.config`:

```properties
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<DESTINATION_SA_API_KEY>" password="<DESTINATION_SA_API_SECRET>";
```

And `source.config`:

```properties
bootstrap.servers=pkc-pgq85.us-west-2.aws.confluent.cloud:9092
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<SOURCE_SA_API_KEY>" password="<SOURCE_SA_API_SECRET>";
consumer.offset.sync.enable=true
consumer.offset.sync.ms=3000
acl.sync.enable=true
```

Results (it fails as expected):

```bash
kafka-cluster-links --create --link my-link \
  --cluster-id $source_id \
  --config-file source.config \
  --bootstrap-server $destination_endpoint \
  --command-config destination.config
Cluster authorization failed.
Error while executing cluster link command: Cluster authorization failed.
[2021-12-01 15:23:33,115] ERROR kafka.common.AdminCommandFailedException: Cluster authorization failed.
        at kafka.admin.ClusterLinkCommand$.throwAdminCommandFailedException$1(ClusterLinkCommand.scala:142)
        at kafka.admin.ClusterLinkCommand$.run(ClusterLinkCommand.scala:148)
        at kafka.admin.ClusterLinkCommand$.main(ClusterLinkCommand.scala:24)
        at kafka.admin.ClusterLinkCommand.main(ClusterLinkCommand.scala)
Caused by: java.util.concurrent.ExecutionException: org.apache.kafka.common.errors.ClusterAuthorizationException: Cluster authorization failed.
        at java.util.concurrent.CompletableFuture.reportGet(CompletableFuture.java:357)
        at java.util.concurrent.CompletableFuture.get(CompletableFuture.java:1908)
        at org.apache.kafka.common.internals.KafkaFutureImpl.get(KafkaFutureImpl.java:165)
        at kafka.admin.ClusterLinkCommand$.createClusterLink(ClusterLinkCommand.scala:168)
        at kafka.admin.ClusterLinkCommand$.run(ClusterLinkCommand.scala:133)
        ... 2 more
Caused by: org.apache.kafka.common.errors.ClusterAuthorizationException: Cluster authorization failed.
 (kafka.admin.ClusterLinkCommand$)
```

### Setting up ACLs

[docs](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/security-cloud.html#creating-or-modifying-a-cluster-link)

> If the user or client application is authenticated with a service account, then their service account needs an ACL to allow them to ALTER the destination cluster. To list the cluster links that exist on a destination cluster, their service account needs an ACL to allow them to DESCRIBE the destination cluster.

```bash
confluent kafka acl create --service-account $destination_service_account --allow --operation alter --cluster-scope
confluent kafka acl create --service-account $destination_service_account --allow --operation describe --cluster-scope
```

Listing ACLs:

```bash
confluent kafka acl list  --service-account $destination_service_account    
Principal    | Permission | Operation | ResourceType | ResourceName  | PatternType  
-----------------+------------+-----------+--------------+---------------+--------------
  User:sa-do11o7 | ALLOW      | ALTER     | CLUSTER      | kafka-cluster | LITERAL      
  User:sa-do11o7 | ALLOW      | DESCRIBE  | CLUSTER      | kafka-cluster | LITERAL  
```

### Creating or modifying a cluster link

```bash
kafka-cluster-links --create --link my-link \
  --cluster-id $source_id \
  --config-file source.config \
  --bootstrap-server $destination_endpoint \
  --command-config destination.config \
  --consumer-group-filters-json-file consumer.offset.sync.all.json \
  --acl-filters-json-file acl.sync.all.json

Cluster link 'my-link' creation successfully completed.
```

where `consumer.offset.sync.all.json`:

```json
{
    "groupFilters": [{
        "name": "*",
        "patternType": "LITERAL",
        "filterType": "INCLUDE"
    }]
}
```

where `acl.sync.all.json`:

```json
{
    "aclFilters": [
        {
            "accessFilter": {
                "operation": "any",
                "permissionType": "any"
            },
            "resourceFilter": {
                "patternType": "any",
                "resourceType": "any"
            }
        }
    ]
}
```

Note: the link is created even if there is no ACL for service account used for source cluster yet.

## Create source topic and populate it

[docs](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/quickstart.html#create-source-and-mirror-topics)

Create a topic `topic-to-link` and put data in it. (I used admin user for that, it is not relevant here).

## Create mirror topic on destination without ACLs

```bash
confluent kafka mirror create topic-to-link --cluster $destination_id --link my-link
Error: REST request failed: While fetching description for topic 'topic-to-link' over cluster link 'my-link': Topic authorization failed. (40301)
Usage:
  confluent kafka mirror create <source-topic-name> [flags]

Examples:
Create a mirror topic `my-topic` under cluster link `my-link`.

  $ confluent kafka mirror create my-topic --link my-link

Create a mirror topic with a custom replication factor and configuration file.

  $ confluent kafka mirror create my-topic --link my-link --replication-factor 5 --config-file my-config.txt

Flags:
      --link string                REQUIRED: The name of the cluster link to attach to the mirror topic.
      --replication-factor int32   Replication factor. (default 3)
      --config-file string         Name of a file with additional topic configuration. Each property should be on its own line with the format: key=value.
      --environment string         Environment ID.
      --cluster string             Kafka cluster ID.
      --context string             CLI context name.

Global Flags:
  -h, --help            Show help for this command.
  -v, --verbose count   Increase verbosity (-v for warn, -vv for info, -vvv for debug, -vvvv for trace).
```

It fails as expected as ACLs are not set on source cluster.


### Permissions for the cluster link to read from the source cluster

[docs](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/security-cloud.html#permissions-for-the-cluster-link-to-read-from-the-source-cluster)

> Allowed to READ and DESCRIBE_CONFIGS for all topics you want to mirror (“source topics”). This will let the cluster link mirror topic data from the source topic to the mirror topic. You could allow the link to read all topics by passing in *, or for specific topics whose names match a prefix, or for specific topic names. Here is an example CLI command to give the cluster link READ access to all topics:

```bash
confluent kafka acl create --allow --service-account $source_service_account --operation READ --operation DESCRIBE_CONFIGS --topic "topic-to-link" --cluster $source_id

    Principal    | Permission |    Operation     | ResourceType | ResourceName  | PatternType  
-----------------+------------+------------------+--------------+---------------+--------------
  User:sa-12nn2j | ALLOW      | READ             | TOPIC        | topic-to-link | LITERAL      
  User:sa-12nn2j | ALLOW      | DESCRIBE_CONFIGS | TOPIC        | topic-to-link | LITERAL 
```

> To sync ACLs (optional), the cluster link must have permissions to DESCRIBE the source cluster. Here is an example of how to specify these permissions.

```bash
confluent kafka acl create --allow --service-account $source_service_account --operation DESCRIBE --cluster-scope --cluster $source_id
    Principal    | Permission | Operation | ResourceType | ResourceName  | PatternType  
-----------------+------------+-----------+--------------+---------------+--------------
  User:sa-12nn2j | ALLOW      | DESCRIBE  | CLUSTER      | kafka-cluster | LITERAL  
```

> To sync consumer group offsets (optional), the cluster link must have permissions to DESCRIBE source topics, and READ and DESCRIBE consumer groups on the source cluster. Here is an example of how to specify these permissions, each of which has to be specified in a separate command:

```bash
confluent kafka acl create --allow --service-account $source_service_account --operation DESCRIBE --topic "topic-to-link" --cluster $source_id
    Principal    | Permission | Operation | ResourceType | ResourceName  | PatternType  
-----------------+------------+-----------+--------------+---------------+--------------
  User:sa-12nn2j | ALLOW      | DESCRIBE  | TOPIC        | topic-to-link | LITERAL 
```

```bash
confluent kafka acl create --allow --service-account $source_service_account --operation READ --operation DESCRIBE --consumer-group "*" --cluster $source_id
    Principal    | Permission | Operation | ResourceType | ResourceName | PatternType  
-----------------+------------+-----------+--------------+--------------+--------------
  User:sa-12nn2j | ALLOW      | READ      | GROUP        | *            | LITERAL      
  User:sa-12nn2j | ALLOW      | DESCRIBE  | GROUP        | *            | LITERAL  
```

### Create mirror topic after ACLs are set

```bash
confluent kafka mirror create topic-to-link --cluster $destination_id --link my-link
Created mirror topic "topic-to-link".
```

# ✅ Verifications

## Consumer offsets

Read 2 messages from source cluster:

```bash
kafka-console-consumer --topic topic-to-link --bootstrap-server $source_endpoint --consumer.config source.config --from-beginning --max-messages 2 --consumer-property group.id=my-consumer-group
1
2
Processed a total of 2 messages
```

Continue to read from destination cluster:

PS: need to set ACLs to do that first:

```bash
confluent kafka acl create --allow --service-account $destination_service_account --operation READ --topic "topic-to-link" --cluster $destination_id
confluent kafka acl create --allow --service-account $destination_service_account --operation READ --operation DESCRIBE --consumer-group "my-consumer-group" --cluster $destination_id
```

```bash
kafka-console-consumer --topic topic-to-link --bootstrap-server $destination_endpoint --consumer.config destination.config --max-messages 8 --consumer-property group.id=my-consumer-group
3
4
5
6
7
8
9
10
```

## Update topic config

Updated `max.message.bytes` to `2097999` on source cluster, it was also updated on destination cluster.


## ACLs sync

On source cluster create an ACL:

```bash
confluent kafka acl create --allow --service-account $source_service_account --operation READ --operation DESCRIBE_CONFIGS --topic "test-acl-sync" --cluster $source_id
```

Verify it is present in destination cluster:

```bash
confluent kafka acl list --service-account $source_service_account
    Principal    | Permission |    Operation     | ResourceType | ResourceName  | PatternType  
-----------------+------------+------------------+--------------+---------------+--------------
  User:sa-12nn2j | ALLOW      | READ             | TOPIC        | test-acl-sync | LITERAL      
```

## Deleting user account that created link and mirror topic

I created a temp OrgAdmin user account and created link `confluent kafka link` and mirror topic using that account and `confluent` CLI.
After deleting the temp OrgAdmin user account, the link is still active and present, and also mirror topic is still working.
