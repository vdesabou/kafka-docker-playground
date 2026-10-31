# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
subject="${args[--subject]}"
id="${args[--id]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

if [[ ! -n "$subject" ]] && [[ ! -n "$id" ]]
then
    logerror "❌ set --subject <subject> or --id <schema id>"
    exit 1
fi

get_sr_url_and_security

# the record name of a schema (avro: namespace.name, protobuf: package.first message, json schema: title)
function schema_record_name() {
    local schema_type="$1"
    local schema="$2"
    case "$schema_type" in
        PROTOBUF)
            local package message
            package=$(echo "$schema" | grep -oE '^\s*package\s+[A-Za-z0-9_.]+' | head -1 | awk '{print $2}')
            message=$(echo "$schema" | grep -oE '^\s*message\s+[A-Za-z0-9_]+' | head -1 | awk '{print $2}')
            echo "${package:+$package.}$message"
            ;;
        JSON)
            echo "$schema" | jq -r '.title // empty' 2> /dev/null
            ;;
        *)
            echo "$schema" | jq -r 'if type == "object" and .name then ((if .namespace and (.name | contains(".") | not) then .namespace + "." else "" end) + .name) else empty end' 2> /dev/null
            ;;
    esac
}

# --id: the schema and every subject / version using it
if [[ -n "$id" ]]
then
    sr_request GET "/schemas/ids/${id}" || sr_exit_on_error "schema id ${id}"
    schema_obj="$sr_response"
    schema_type=$(echo "$schema_obj" | jq -r '.schemaType // "AVRO"')
    record_name=$(schema_record_name "$schema_type" "$(echo "$schema_obj" | jq -r .schema)")
    used_by="[]"
    sr_request GET "/schemas/ids/${id}/versions?deleted=true" && used_by="$sr_response"
    live_used_by="[]"
    sr_request GET "/schemas/ids/${id}/versions" && live_used_by="$sr_response"
    result=$(jq -n --argjson id "$id" --arg t "$schema_type" --arg name "$record_name" --argjson all "$used_by" --argjson live "$live_used_by" --argjson obj "$schema_obj" \
        '{id: $id, schema_type: $t, record_name: (if $name == "" then null else $name end), references: ($obj.references // []),
          used_by: [$all[] | . as $v | . + {deleted: (($live | map(select(.subject == $v.subject and .version == $v.version)) | length) == 0)}]}')
    if [[ -n "$json" ]]
    then
        echo "$result"
        exit 0
    fi
    log "💯 schema id ${id}: ${schema_type}${record_name:+ $record_name}"
    if [ "$(echo "$result" | jq '.used_by | length')" == "0" ]
    then
        log "   used by no subject any more (all its versions were permanently deleted, but the id still resolves while the registry keeps it)"
    else
        echo "$result" | jq -r '.used_by[] | "   🔰 \(.subject) v\(.version)\(if .deleted then " 🧟 soft deleted" else "" end)"'
    fi
    echo "$result" | jq -r '.references[] | "   🔗 references \(.subject) v\(.version) as \(.name)"'
    exit 0
fi

encoded_subject=$(urlencode "$subject")
sr_request GET "/subjects/${encoded_subject}/versions?deleted=true" || sr_exit_on_error "subject ${subject}"
all_versions=$(echo "$sr_response" | jq -r '.[]')
live_versions=""
sr_request GET "/subjects/${encoded_subject}/versions" && live_versions=$(echo "$sr_response" | jq -r '.[]')

# compatibility, mode and alias, with their source
compatibility_source="subject"
alias_target=""
if sr_request GET "/config/${encoded_subject}"
then
    compatibility=$(echo "$sr_response" | jq -r '.compatibilityLevel // .compatibility // empty')
    alias_target=$(echo "$sr_response" | jq -r '.alias // empty')
    subject_config="$sr_response"
else
    subject_config="{}"
fi
if [ -z "$compatibility" ]
then
    sr_global_compatibility
    compatibility="$sr_global_compatibility_value"
    compatibility_source="global"
fi
mode_source="subject"
if sr_request GET "/mode/${encoded_subject}"
then
    mode=$(echo "$sr_response" | jq -r .mode)
else
    sr_request GET "/mode" && mode=$(echo "$sr_response" | jq -r .mode)
    mode_source="global"
fi

versions_file="$(mktemp -t pg-XXXXXXXXXX)"
trap 'rm -f $versions_file' EXIT
latest_schema=""
latest_type=""
for v in $all_versions
do
    sr_request GET "/subjects/${encoded_subject}/versions/${v}?deleted=true" || continue
    obj="$sr_response"
    vid=$(echo "$obj" | jq -r .id)
    deleted=true
    echo "$live_versions" | grep -qx "$v" && deleted=false
    referenced_by="[]"
    if sr_request GET "/subjects/${encoded_subject}/versions/${v}/referencedby"
    then
        ids=$(echo "$sr_response" | jq -r '.[]')
        refs="[]"
        for rid in $ids
        do
            if sr_request GET "/schemas/ids/${rid}/versions"
            then
                refs=$(echo "$refs" | jq --argjson more "$sr_response" --argjson rid "$rid" '. + [$more[] | . + {id: $rid}]')
            fi
        done
        referenced_by="$refs"
    fi
    shared="[]"
    if sr_request GET "/schemas/ids/${vid}/versions?deleted=true"
    then
        shared=$(echo "$sr_response" | jq --arg s "$subject" '[.[] | select(.subject != $s)]')
    fi
    echo "$obj" | jq -c --argjson deleted "$deleted" --argjson rb "$referenced_by" --argjson shared "$shared" \
        '{version, id, schema_type: (.schemaType // "AVRO"), deleted: $deleted, ts: (.ts // null), references: (.references // []),
          referenced_by: $rb, same_id_in: $shared, metadata: (.metadata // null), ruleSet: (.ruleSet // null)}' >> "$versions_file"
    if [ "$deleted" == "false" ]
    then
        latest_schema=$(echo "$obj" | jq -r .schema)
        latest_type=$(echo "$obj" | jq -r '.schemaType // "AVRO"')
    fi
done

# the subject name strategy the name suggests, and the topic it belongs to
record_name=$(schema_record_name "$latest_type" "$latest_schema")
strategy="unknown"
topic=""
case "$subject" in
    *-key|*-value)
        strategy="TopicNameStrategy"
        topic="${subject%-*}"
        ;;
esac
if [ -n "$record_name" ]
then
    if [ "$subject" == "$record_name" ]
    then
        strategy="RecordNameStrategy"
        topic=""
    elif [[ "$subject" == *"-$record_name" ]]
    then
        strategy="TopicRecordNameStrategy"
        topic="${subject%-$record_name}"
    fi
fi
topic_exists=null
if [ -n "$topic" ] && [[ "$environment" != "ccloud" ]]
then
    if playground get-topic-list 2> /dev/null | grep -qxF "$topic"
    then
        topic_exists=true
    else
        topic_exists=false
    fi
fi

result=$(jq -s --arg subject "$subject" --arg compatibility "$compatibility" --arg cs "$compatibility_source" \
    --arg mode "$mode" --arg ms "$mode_source" --arg alias "$alias_target" --arg record "$record_name" \
    --arg strategy "$strategy" --arg topic "$topic" --argjson topic_exists "$topic_exists" --argjson config "$subject_config" \
    '{subject: $subject, compatibility: $compatibility, compatibility_source: $cs, mode: $mode, mode_source: $ms,
      alias: (if $alias == "" then null else $alias end),
      settings: ($config | del(.compatibilityLevel, .compatibility, .alias)),
      record_name: (if $record == "" then null else $record end), subject_name_strategy: $strategy,
      topic: (if $topic == "" then null else $topic end), topic_exists: $topic_exists,
      versions: .}' "$versions_file")

if [[ -n "$json" ]]
then
    echo "$result"
    exit 0
fi

log "🔰 subject ${subject}"
echo "$result" | jq -r '
  "   🛡️ compatibility  \(.compatibility)\(if .compatibility_source == "global" then " 🌍 (global, no subject-level rule)" else " (subject-level)" end)",
  "   🔏 mode           \(.mode)\(if .mode_source == "global" then " 🌍 (global)" else " (subject-level)" end)",
  (if .alias then "   🔯 alias of       \(.alias)" else empty end),
  (if (.settings | length) > 0 then "   ⚙️ settings       \(.settings | tojson)" else empty end),
  "   🏷️ record name    \(.record_name // "?")",
  "   🧭 strategy       \(.subject_name_strategy)\(if .topic then " → topic \(.topic)\(if .topic_exists == false then " ❗ (no such topic)" elif .topic_exists then " ✅" else "" end)" else "" end)",
  "   📚 versions",
  (.versions[] |
    "      \(if .deleted then "🧟" else "💯" end) v\(.version)  id \(.id)  \(.schema_type)\(if .ts then "  " + ((.ts / 1000) | strflocaltime("%Y-%m-%d %H:%M:%S")) else "" end)\(if .deleted then "  soft deleted" else "" end)",
    (.references[] | "         🔗 references \(.subject) v\(.version) as \(.name)"),
    (.referenced_by[] | "         ⬅️ referenced by \(.subject) v\(.version) (id \(.id)): can'"'"'t be deleted before it"),
    (.same_id_in[] | "         👯 same schema (id) in \(.subject) v\(.version)"),
    (if .metadata then "         🟡 metadata \(.metadata | tojson)" else empty end),
    (if .ruleSet then "         📏 ruleSet \(.ruleSet | tojson)" else empty end))'
