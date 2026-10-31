# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
subject="${args[--subject]}"
version="${args[--version]}"
json="${args[--json]}"
verbose="${args[--verbose]}"
eval "records=(${args[--record]})"

get_sr_url_and_security
if [[ "$environment" != "plaintext" ]]
then
    logerror "❌ schema test-rules runs the console producer of the schema-registry container: only on the plaintext environment (running: $environment)"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
tmp_name="playground-schema-check-$$-$RANDOM"
tmp_subject_created=0
function cleanup_test_rules() {
    local rc=$?
    if [ $tmp_subject_created -eq 1 ]
    then
        sr_request DELETE "/subjects/${tmp_name}-value" > /dev/null
        sr_request DELETE "/subjects/${tmp_name}-value?permanent=true" > /dev/null
        playground topic delete --topic "$tmp_name" --skip-delete-schema > /dev/null 2>&1
    fi
    rm -rf "$tmp_dir"
    return $rc
}
trap cleanup_test_rules EXIT

# the records: --record (repeatable), else stdin, one json per line
records_file="$tmp_dir/records"
if [ "${#records[@]}" -gt 0 ]
then
    printf '%s\n' "${records[@]}" > "$records_file"
else
    if [ -t 0 ]
    then
        logerror "❌ give the records with --record '<json>' or on stdin, one json per line"
        exit 1
    fi
    grep -v '^\s*$' > "$records_file"
fi

encoded_subject=$(urlencode "$subject")
sr_request GET "/subjects/${encoded_subject}/versions/${version}" || sr_exit_on_error "subject ${subject} version ${version}"
obj="$sr_response"
schema_type=$(echo "$obj" | jq -r '.schemaType // "AVRO"')
if ! echo "$obj" | jq -e '.ruleSet != null' > /dev/null 2>&1
then
    logerror "❌ ${subject} v$(echo "$obj" | jq -r .version) has no ruleSet: nothing to test"
    logerror "   register one with 'playground schema register --subject ${subject} --rule <name>:<CEL expression>' (or --rule-set)"
    exit 1
fi
if echo "$obj" | jq -e '(.references // []) | length > 0' > /dev/null
then
    logerror "❌ schemas with references are not supported by schema test-rules"
    exit 1
fi
case "$schema_type" in
    AVRO) producer=kafka-avro-console-producer ;;
    JSON) producer=kafka-json-schema-console-producer ;;
    PROTOBUF) producer=kafka-protobuf-console-producer ;;
esac
rule_names=$(echo "$obj" | jq -r '[(.ruleSet.domainRules // [])[], (.ruleSet.migrationRules // [])[]] | map("\(.name) (\(.kind) \(.type) \(.mode)\(if .onFailure then ", onFailure " + .onFailure else "" end))") | join(", ")')
[[ -n "$json" ]] || log "📏 ${subject} v$(echo "$obj" | jq -r .version) (id $(echo "$obj" | jq -r .id)): ${rule_names}"

# a temporary subject with the same schema and rules (same id), and its topic: the serializer runs the rules of the
# latest version of <topic>-value, nothing is written to the topics of the subject
copy_body=$(echo "$obj" | jq -c '{schema, schemaType: (.schemaType // "AVRO"), references: (.references // [])} + (if .metadata then {metadata} else {} end) + {ruleSet}')
sr_request POST "/subjects/${tmp_name}-value/versions" "$copy_body" || sr_exit_on_error "temporary subject"
tmp_subject_created=1
schema_string=$(echo "$obj" | jq -r .schema)

results_file="$tmp_dir/results.jsonl"
: > "$results_file"
nb_failed=0
while IFS= read -r record
do
    output=$(echo "$record" | docker exec -i schema-registry "$producer" --bootstrap-server broker:9092 --topic "$tmp_name" \
        --property schema.registry.url=http://schema-registry:8081 --property auto.register.schemas=false \
        --property use.latest.version=true --property latest.compatibility.strict=false \
        --property "value.schema=$schema_string" 2>&1)
    ret=$?
    if [ $ret -eq 0 ]
    then
        jq -cn --arg r "$record" '{record: $r, passed: true}' >> "$results_file"
        [[ -n "$json" ]] || log "✅ $record"
    else
        nb_failed=$((nb_failed+1))
        rule=$(echo "$output" | grep -oE "Rule failed: [^ ]+" | head -1 | sed -e 's/Rule failed: //')
        expr=$(echo "$output" | grep -oE "Expr failed: .*" | head -1 | sed -e 's/^Expr failed: //')
        reason=$(echo "$output" | grep -E "Caused by|Exception" | grep -v "^\s" | tail -1 | cut -c1-300)
        jq -cn --arg r "$record" --arg rule "$rule" --arg expr "$expr" --arg reason "$reason" \
            '{record: $r, passed: false, rule: (if $rule == "" then null else $rule end), expr: (if $expr == "" then null else $expr end), reason: $reason}' >> "$results_file"
        if [[ ! -n "$json" ]]
        then
            if [ -n "$rule" ]
            then
                logerror "❌ $record"
                logerror "   rule ${rule} failed: ${expr}"
            else
                logerror "❌ $record: ${reason}"
            fi
        fi
    fi
done < "$records_file"

if [[ -n "$json" ]]
then
    jq -s --arg s "$subject" '{subject: $s, passed: (map(select(.passed)) | length), failed: (map(select(.passed | not)) | length), records: .}' "$results_file"
else
    log "🧭 $(( $(wc -l < "$results_file") - nb_failed )) passed, ${nb_failed} failed: a failed record is refused by a producer using this version (use.latest.version=true), or sent to its DLQ with onFailure DLQ"
fi
if [ $nb_failed -gt 0 ]
then
    exit 1
fi
exit 0
