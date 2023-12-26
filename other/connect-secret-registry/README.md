# Connect Secret Registry

## Objective

Quickly test [Connect Secret Registry](https://docs.confluent.io/platform/current/connect/rbac/connect-rbac-secret-registry.html#kconnect-secret-registry).

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Rolebindings explained [here](https://docs.confluent.io/platform/current/connect/rbac/connect-rbac-connect-cluster.html#configuring-rbac-for-a-kconnect-cluster) are already specified in playground's RBAC environment [here](https://github.com/vdesabou/kafka-docker-playground/blob/83d37281dec01193386aa39a551725bceb77cfa0/environment/rbac-sasl-plain/scripts/helper/create-role-bindings.sh#L100-L116):

```bash
# ResourceOwner for groups and topics on broker
declare -a ConnectResources=(
    "Topic:connect-configs"
    "Topic:connect-offsets"
    "Topic:connect-status"
    "Group:connect-cluster"
    "Topic:_confluent-monitoring"
    "Topic:_confluent-secrets"     <------ here
    "Group:secret-registry"        <------ here
)
for resource in ${ConnectResources[@]}
do
    confluent iam rolebinding create \
        --principal $CONNECT_ADMIN \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
```
