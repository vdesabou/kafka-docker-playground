principal="${args[--principal]}"
verbose="${args[--verbose]}"

entry_filter='{"operation": "ANY", "permissionType": "ANY"}'
kafka_acls_principal=""
if [[ -n "$principal" ]]
then
  principal=$(normalize_rbac_principal "$principal")
  entry_filter=$(jq -nc --arg principal "$principal" '{principal: $principal, operation: "ANY", permissionType: "ANY"}')
  kafka_acls_principal="--principal $principal"
fi

get_mds_scope kafka || exit 1
mds_request POST "/security/1.0/acls:search" "$(jq -nc --argjson scope "$mds_scope" --argjson entry "$entry_filter" '{scope: $scope, aclBindingFilter: {patternFilter: {resourceType: "ANY", patternType: "ANY"}, entryFilter: $entry}}')" || exit 1
rows=$(jq -r '.[] | [.entry.principal, .entry.permissionType, .entry.operation, "\(.pattern.resourceType):\(.pattern.name)", .pattern.patternType, .entry.host, "centralized"] | @tsv' <<< "$mds_output")

# regular Kafka ACLs, kafka-acls --list prints:
# Current ACLs for resource `ResourcePattern(resourceType=TOPIC, name=foo, patternType=LITERAL)`:
#  	(principal=User:charlie, host=*, operation=READ, permissionType=ALLOW)
kafka_acls_output=$(playground container exec -c broker --command "kafka-acls --bootstrap-server broker:9092 --command-config /etc/kafka/secrets/client_without_interceptors.config --list $kafka_acls_principal" 2>/dev/null)
kafka_rows=$(awk '
  /ResourcePattern\(/ {
    match($0, /resourceType=[^,]*/); type = substr($0, RSTART + 13, RLENGTH - 13)
    match($0, /name=[^,]*/); name = substr($0, RSTART + 5, RLENGTH - 5)
    match($0, /patternType=[^)]*/); pattern = substr($0, RSTART + 12, RLENGTH - 12)
  }
  /\(principal=/ {
    match($0, /principal=[^,]*/); p = substr($0, RSTART + 10, RLENGTH - 10)
    match($0, /host=[^,]*/); host = substr($0, RSTART + 5, RLENGTH - 5)
    match($0, /operation=[^,]*/); op = substr($0, RSTART + 10, RLENGTH - 10)
    match($0, /permissionType=[^)]*/); perm = substr($0, RSTART + 15, RLENGTH - 15)
    printf "%s\t%s\t%s\t%s:%s\t%s\t%s\tkafka-acls\n", p, perm, op, type, name, pattern, host
  }' <<< "$kafka_acls_output")

rows=$(printf "%s\n%s\n" "$rows" "$kafka_rows" | grep -v '^$' || true)
# same resource type names as the --resource flag (TOPIC:orders -> Topic:orders)
rows=$(awk -F'\t' -v OFS='\t' '{ sub(/^TOPIC:/, "Topic:", $4); sub(/^GROUP:/, "Group:", $4); sub(/^CLUSTER:/, "Cluster:", $4); sub(/^TRANSACTIONAL_ID:/, "TransactionalId:", $4); sub(/^DELEGATION_TOKEN:/, "DelegationToken:", $4); print }' <<< "$rows")
if [[ -z "$rows" ]]
then
  logwarn "no ACL found"
  exit 0
fi

{
  printf "PRINCIPAL\tPERMISSION\tOPERATION\tRESOURCE\tPATTERN\tHOST\tSTORE\n"
  echo "$rows"
} | column -t -s $'\t'
