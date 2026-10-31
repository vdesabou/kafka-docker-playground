# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
subject="${args[--subject]}"
json="${args[--json]}"
keep="${args[--keep]}"
verbose="${args[--verbose]}"
eval "cp_versions=(${args[--cp-version]})"
eval "schemas=(${args[--schema]})"

get_environment_used
if [[ "$environment" == "ccloud" ]] || [[ "$environment" == cfk* ]]
then
    logerror "❌ schema validate starts Schema Registry containers next to the broker of a docker environment (running: $environment)"
    exit 1
fi
get_broker_container
if [ -z "$broker_container" ] || ! docker inspect "$broker_container" > /dev/null 2>&1
then
    logerror "❌ no broker running: schema validate needs a running environment (its Schema Registry containers store their schemas in it)"
    exit 1
fi
network=$(docker inspect "$broker_container" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
bootstrap="${broker_container}:9092"
image="${CP_SCHEMA_REGISTRY_IMAGE:-confluentinc/cp-schema-registry}"

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
containers=()
topics=()
function cleanup_validate() {
    local rc=$?
    local c t
    if [[ ! -n "$keep" ]]
    then
        for c in "${containers[@]}"
        do
            docker rm -f "$c" > /dev/null 2>&1
        done
        for t in "${topics[@]}"
        do
            playground topic delete --topic "$t" --skip-delete-schema > /dev/null 2>&1
        done
    fi
    rm -rf "$tmp_dir"
    return $rc
}
trap cleanup_validate EXIT

# the schemas: --schema (repeatable, registered in that order), else stdin
schema_files=()
if [ "${#schemas[@]}" -eq 0 ]
then
    schemas=("-")
fi
i=0
for schema in "${schemas[@]}"
do
    i=$((i+1))
    f="$tmp_dir/schema-$i"
    sr_read_schema_arg "$schema" "$f" || exit 1
    if ! sr_schema_request_body "$f"
    then
        logerror "❌ no known schema could be identified in ${schema}"
        exit 1
    fi
    echo "$sr_body" > "$f.body"
    if [[ $schema == @* ]] || [ -f "$schema" ]
    then
        echo "$(basename "${schema#@}")" > "$f.label"
    else
        echo "schema $i" > "$f.label"
    fi
    schema_files+=("$f")
done

results="$tmp_dir/results.jsonl"
: > "$results"
for version in "${cp_versions[@]}"
do
    name="playground-schema-validate-$(echo "$version" | tr -c 'a-zA-Z0-9\n' '-')-$$"
    topic="_schemas_$(echo "$name" | tr '-' '_')"
    [[ -n "$json" ]] || log "🐳 Schema Registry ${version}: starting ${image}:${version}"
    if ! docker image inspect "${image}:${version}" > /dev/null 2>&1
    then
        if ! docker pull "${image}:${version}" > "$tmp_dir/pull-$version.log" 2>&1
        then
            logerror "❌ can't pull ${image}:${version}"
            tail -3 "$tmp_dir/pull-$version.log"
            jq -cn --arg v "$version" '{cp_version: $v, error: "image not found"}' >> "$results"
            continue
        fi
    fi
    containers+=("$name")
    topics+=("$topic")
    docker run -d --name "$name" --network "$network" -p 127.0.0.1::8081 \
        -e SCHEMA_REGISTRY_HOST_NAME="$name" \
        -e SCHEMA_REGISTRY_LISTENERS=http://0.0.0.0:8081 \
        -e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS="$bootstrap" \
        -e SCHEMA_REGISTRY_KAFKASTORE_TOPIC="$topic" \
        -e SCHEMA_REGISTRY_KAFKASTORE_TOPIC_REPLICATION_FACTOR=1 \
        -e SCHEMA_REGISTRY_SCHEMA_REGISTRY_GROUP_ID="$name" \
        "${image}:${version}" > /dev/null || { logerror "❌ can't start ${image}:${version}"; continue; }
    port=$(docker port "$name" 8081 | head -1 | awk -F: '{print $NF}')
    url="http://127.0.0.1:${port}"
    ready=0
    for i in $(seq 1 60)
    do
        if curl -s "${url}/subjects" 2> /dev/null | jq -e 'type == "array"' > /dev/null 2>&1
        then
            ready=1
            break
        fi
        if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2> /dev/null)" != "true" ]
        then
            break
        fi
        sleep 2
    done
    if [ $ready -eq 0 ]
    then
        logerror "❌ Schema Registry ${version} did not start (old clients can't talk to a newer broker: CP 5.x / 6.0 with a CP 8 environment)"
        docker logs "$name" 2>&1 | grep -E "ERROR|Exception" | head -3
        jq -cn --arg v "$version" '{cp_version: $v, error: "did not start"}' >> "$results"
        continue
    fi
    for f in "${schema_files[@]}"
    do
        label=$(cat "$f.label")
        response=$(curl -s -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" --data @"$f.body" "${url}/subjects/$(urlencode "$subject")/versions")
        if echo "$response" | jq -e 'has("id")' > /dev/null 2>&1
        then
            jq -cn --arg v "$version" --arg s "$label" --argjson r "$response" '{cp_version: $v, schema: $s, accepted: true, version: $r.version, id: $r.id}' >> "$results"
            [[ -n "$json" ]] || log "   ✅ ${label}: accepted (id $(echo "$response" | jq -r .id))"
        else
            code=$(echo "$response" | jq -r '.error_code // "?"' 2> /dev/null)
            message=$(echo "$response" | jq -r '.message // .' 2> /dev/null)
            jq -cn --arg v "$version" --arg s "$label" --arg c "$code" --arg m "$message" '{cp_version: $v, schema: $s, accepted: false, error_code: $c, message: $m}' >> "$results"
            # the reason is after the last "details: " (the registry repeats the whole schema before it)
            [[ -n "$json" ]] || logerror "   ❌ ${label}: ${code} $(echo "$message" | sed -e 's/.*details: //' | cut -c1-250)"
        fi
    done
done

if [[ -n "$json" ]]
then
    jq -s '{results: .}' "$results"
else
    echo ""
    log "🧭 Verdict per CP version (each version starts with an empty registry and its default settings)"
    {
        echo -e "SCHEMA\t$(printf '%s\t' "${cp_versions[@]}")"
        for f in "${schema_files[@]}"
        do
            label=$(cat "$f.label")
            row="$label"
            for version in "${cp_versions[@]}"
            do
                cell=$(jq -r --arg v "$version" --arg s "$label" 'select(.cp_version == $v and (.schema == $s or .error != null)) | if .error then "⚠️ " + .error elif .accepted then "✅" else "❌ " + .error_code end' "$results" | head -1)
                row="${row}\t${cell:-?}"
            done
            echo -e "$row"
        done
    } | column -t -s $'\t'
    [[ -n "$keep" ]] && log "🐳 kept: ${containers[*]} (docker rm -f them, and delete the topics ${topics[*]})"
fi
if jq -e 'select(.accepted == false)' "$results" > /dev/null 2>&1 && [ -n "$(jq -c 'select(.accepted == false)' "$results")" ]
then
    exit 1
fi
exit 0
