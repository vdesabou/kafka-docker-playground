# Cluster Linking Quick Start with service account only

This is the [quickstart](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/quickstart.html) that is being followed here, but with requirement to use only service accounts (least privileges principle).

❗ This is not an automated test, just some notes of the tests done. ❗

*EDIT*: there is a documented example with service accounts [here](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/topic-data-sharing.html#share-data-across-clusters-regions-and-clouds) 

- [Cluster Linking Quick Start with service account only](#cluster-linking-quick-start-with-service-account-only)
  - [🏁 Prerequisites](#-prerequisites)
    - [Create source and destination clusters](#create-source-and-destination-clusters)
    - [Create source topic and populate it](#create-source-topic-and-populate-it)
    - [Create service accounts and API keys](#create-service-accounts-and-api-keys)
      - [Source cluster](#source-cluster)
      - [Destination cluster](#destination-cluster)
    - [Setting up ACLs](#setting-up-acls)
      - [Destination](#destination)
      - [Source](#source)
  - [🔗 Creating Cluster Link](#-creating-cluster-link)
    - [Using `confluent` CLI (not working)](#using-confluent-cli-not-working)
      - [Using `kafka-cluster-links` CLI (working)](#using-kafka-cluster-links-cli-working)
  - [🪞 Create mirror topic on destination](#-create-mirror-topic-on-destination)
    - [Using `confluent` CLI](#using-confluent-cli)
    - [Using `kafka-mirrors` CLI](#using-kafka-mirrors-cli)
- [✅ Verifications](#-verifications)
  - [Consumer offsets](#consumer-offsets)
  - [Update topic config](#update-topic-config)
  - [ACLs sync](#acls-sync)
  - [Deleting user account that created link and mirror topic](#deleting-user-account-that-created-link-and-mirror-topic)
  - [Stop consumer offset sync for consumer group my-consumer-group](#stop-consumer-offset-sync-for-consumer-group-my-consumer-group)

## 🏁 Prerequisites
### Create source and destination clusters

```bash
confluent kafka cluster create VincentClusterLinkingSource --type basic --cloud aws --region us-west-2
```

```bash
confluent kafka cluster create VincentClusterLinkingDestination --type dedicated --cloud aws --region us-east-1 --cku 1 --availability single-zone
```

```
source_id=lkc-65176
source_endpoint=pkc-pgq85.us-west-2.aws.confluent.cloud:9092
destination_id=lkc-nz953
destination_endpoint=pkc-6o99j.us-east-1.aws.confluent.cloud:9092
```

### Create source topic and populate it

[docs](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/quickstart.html#create-source-and-mirror-topics)

Create a topic `topic-to-link` and put data in it. (I used admin user for that with UI, it is not relevant here).

### Create service accounts and API keys

#### Source cluster

```bash
confluent iam service-account create SA-Source-ClusterLinking --description "SA for Source cluster" 

+-------------+-----------------------+
| ID          | sa-81g8qq             |
| Name        | SA-Source-ClusterLinking     |
| Description | SA for Source cluster |
+-------------+-----------------------+
```

```
source_service_account=sa-81g8qq
```

```bash
confluent api-key create --resource $source_id --service-account $source_service_account --description "api key for SA-ClusterLinking"
It may take a couple of minutes for the API key to be ready.
Save the API key and secret. The secret is not retrievable later.
+---------+------------------------------------------------------------------+
| API Key | <SOURCE_SA_API_KEY>                                                 |
| Secret  | <SOURCE_SA_API_SECRET> |
+---------+------------------------------------------------------------------+
```

```
source_api_key="<SOURCE_SA_API_KEY>"
source_api_secret="<SOURCE_SA_API_SECRET>"
```

#### Destination cluster

```bash
confluent iam service-account create SA--Destination-ClusterLinking --description "SA for Destination cluster" 
+-------------+--------------------------------+
| ID          | sa-k8jr62                      |
| Name        | SA--Destination-ClusterLinking |
| Description | SA for Destination cluster     |
+-------------+--------------------------------+
```

```
destination_service_account=sa-k8jr62
```

```bash
confluent api-key create --resource $destination_id --service-account $destination_service_account --description "api key for SA-ClusterLinking"
It may take a couple of minutes for the API key to be ready.
Save the API key and secret. The secret is not retrievable later.
+---------+------------------------------------------------------------------+
| API Key | <DESTINATION_SA_API_KEY>                                                 |
| Secret  | <DESTINATION_SA_API_SECRET> |
+---------+------------------------------------------------------------------+
```

```
destination_api_key="<DESTINATION_SA_API_KEY>"
destination_api_secret="<DESTINATION_SA_API_SECRET>"
```

### Setting up ACLs

See summary table [there](https://docs.confluent.io/platform/current/multi-dc-deployments/cluster-linking/security.html#authorization-acls).

#### Destination

[docs](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/security-cloud.html#creating-or-modifying-a-cluster-link)

> If the user or client application is authenticated with a service account, then their service account needs an ACL to allow them to ALTER the destination cluster. To list the cluster links that exist on a destination cluster, their service account needs an ACL to allow them to DESCRIBE the destination cluster.

```bash
confluent kafka acl create --service-account $destination_service_account --allow --operations alter --cluster-scope
confluent kafka acl create --service-account $destination_service_account --allow --operations describe --cluster-scope
confluent kafka acl create --service-account $destination_service_account --allow --operations alter-configs --cluster-scope
```

To allow to create and alter mirror topic:

```bash
confluent kafka acl create --allow --service-account $destination_service_account --operations CREATE --operations ALTER --topic "topic-to-link" --cluster $destination_id

    Principal    | Permission | Operation | ResourceType | ResourceName  | PatternType  
-----------------+------------+-----------+--------------+---------------+--------------
  User:sa-k8jr62 | ALLOW      | CREATE    | TOPIC        | topic-to-link | LITERAL      
  User:sa-k8jr62 | ALLOW      | ALTER     | TOPIC        | topic-to-link | LITERAL  
```

#### Source

[docs](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/security-cloud.html#permissions-for-the-cluster-link-to-read-from-the-source-cluster)

> Allowed to READ and DESCRIBE_CONFIGS for all topics you want to mirror (“source topics”). This will let the cluster link mirror topic data from the source topic to the mirror topic. You could allow the link to read all topics by passing in *, or for specific topics whose names match a prefix, or for specific topic names. Here is an example CLI command to give the cluster link READ access to all topics:

```bash
confluent kafka acl create --allow --service-account $source_service_account --operations READ --operations DESCRIBE_CONFIGS --topic "topic-to-link" --cluster $source_id

    Principal    | Permission |    Operation     | ResourceType | ResourceName  | PatternType  
-----------------+------------+------------------+--------------+---------------+--------------
  User:sa-81g8qq | ALLOW      | READ             | TOPIC        | topic-to-link | LITERAL      
  User:sa-81g8qq | ALLOW      | DESCRIBE_CONFIGS | TOPIC        | topic-to-link | LITERAL 
```

> To sync ACLs (optional), the cluster link must have permissions to DESCRIBE the source cluster. Here is an example of how to specify these permissions.

```bash
confluent kafka acl create --allow --service-account $source_service_account --operations DESCRIBE --cluster-scope --cluster $source_id
    Principal    | Permission | Operation | ResourceType | ResourceName  | PatternType  
-----------------+------------+-----------+--------------+---------------+--------------
  User:sa-81g8qq | ALLOW      | DESCRIBE  | CLUSTER      | kafka-cluster | LITERAL  
```

> To sync consumer group offsets (optional), the cluster link must have permissions to DESCRIBE source topics, and READ and DESCRIBE consumer groups on the source cluster. Here is an example of how to specify these permissions, each of which has to be specified in a separate command:

```bash
confluent kafka acl create --allow --service-account $source_service_account --operations DESCRIBE --topic "topic-to-link" --cluster $source_id
    Principal    | Permission | Operation | ResourceType | ResourceName  | PatternType  
-----------------+------------+-----------+--------------+---------------+--------------
  User:sa-81g8qq | ALLOW      | DESCRIBE  | TOPIC        | topic-to-link | LITERAL 
```

```bash
confluent kafka acl create --allow --service-account $source_service_account --operations READ --operations DESCRIBE --consumer-group "*" --cluster $source_id
    Principal    | Permission | Operation | ResourceType | ResourceName | PatternType  
-----------------+------------+-----------+--------------+--------------+--------------
  User:sa-81g8qq | ALLOW      | READ      | GROUP        | *            | LITERAL      
  User:sa-81g8qq | ALLOW      | DESCRIBE  | GROUP        | *            | LITERAL  
```

## 🔗 Creating Cluster Link

### Using `confluent` CLI (not working)

There is no way to specify that we want to use service account for destination cluster. For source cluster, this is ok because we can use `source-api-key`  

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

Trying with context:

```bash
 confluent context create destination-using-sa-context --bootstrap $destination_endpoint --api-key $destination_api_key --api-secret $destination_api_secret 
+------------+----------------------------------------------+
| Name       | destination-using-sa-context                 |
| Platform   | $destination_endpoint |
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

#### Using `kafka-cluster-links` CLI (working)

It seems to be required to use `kafka-cluster-links` when we want to use service accounts only:

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

Results:

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
## 🪞 Create mirror topic on destination

### Using `confluent` CLI

```bash
confluent kafka mirror create topic-to-link --cluster $destination_id --link my-link --config-file destination.config
Created mirror topic "topic-to-link".
```

### Using `kafka-mirrors` CLI

We can also used `kafka-mirrors` CLI:

```bash
kafka-mirrors --create --mirror-topic topic-to-link --link my-link --bootstrap-server $destination_endpoint --command-config destination.config
```

# ✅ Verifications

## Consumer offsets

Read 2 messages from source cluster:

```bash
playground topic consume --topic topic-to-link --min-expected-messages 2 --timeout 60
1
2
Processed a total of 2 messages
```

Continue to read from destination cluster:

PS: need to set ACLs to do that first:

```bash
confluent kafka acl create --allow --service-account $destination_service_account --operations READ --topic "topic-to-link" --cluster $destination_id
confluent kafka acl create --allow --service-account $destination_service_account --operations READ --operations DESCRIBE --consumer-group "my-consumer-group" --cluster $destination_id
```

```bash
playground topic consume --topic topic-to-link --min-expected-messages 8 --timeout 60
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
confluent kafka acl create --allow --service-account $source_service_account --operations READ --operations DESCRIBE_CONFIGS --topic "test-acl-sync" --cluster $source_id
```

Verify it is present in destination cluster:

```bash
confluent kafka cluster use $destination_id
confluent kafka acl list | grep $source_service_account
    Principal    | Permission |    Operation     | ResourceType | ResourceName  | PatternType  
-----------------+------------+------------------+--------------+---------------+--------------
  User:sa-81g8qq | ALLOW      | READ             | TOPIC        | test-acl-sync | LITERAL      
```

## Deleting user account that created link and mirror topic

I created a temp OrgAdmin user account and created link `confluent kafka link` and mirror topic using that account and `confluent` CLI.
After deleting the temp OrgAdmin user account, the link is still active and present, and also mirror topic is still working.

## Stop consumer offset sync for consumer group my-consumer-group

```bash
echo "consumer.offset.group.filters={\"groupFilters\": [ \
  { \
    \"name\": \"*\", \
    \"patternType\": \"LITERAL\", \
    \"filterType\": \"INCLUDE\" \
  }, \
  { \
    \"name\": \"my-consumer-group\", \
    \"patternType\": \"LITERAL\", \
    \"filterType\": \"EXCLUDE\" \
  } \
]}" > newFilters.properties

kafka-configs --bootstrap-server $destination_endpoint --alter --cluster-link my-link --add-config-file newFilters.properties --command-config destination.config
Completed updating config for cluster-link my-link.
```
