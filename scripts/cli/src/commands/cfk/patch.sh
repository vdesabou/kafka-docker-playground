resource="${args[resource]}"
patch="${args[patch]}"
type="${args[--type]}"
timeout="${args[--timeout]}"
no_wait="${args[--no-wait]}"

if [[ "$resource" != */* ]]
then
    logerror "❌ give the custom resource as kind/name, for example kafka/kafka (one of: $(cfk_cr_list | tr '\n' ' '))"
    exit 1
fi
if ! kubectl -n confluent get "$resource" > /dev/null 2>&1
then
    logerror "❌ custom resource $resource not found in namespace confluent, the custom resources are: $(cfk_cr_list | tr '\n' ' ')"
    exit 1
fi
if [[ "$patch" != \{* ]] && [[ "$patch" != \[* ]]
then
    # YAML patch: kubectl patch only takes JSON
    if ! patch=$(echo "$patch" | yq -o=json -I=0 '.' 2>&1)
    then
        logerror "❌ the patch is neither JSON nor YAML: $patch"
        exit 1
    fi
fi
log "🩹 kubectl patch $resource --type $type -p '$patch'"
cfk_patch_and_wait "$resource" "$patch" "$type" "$timeout" "$no_wait"
