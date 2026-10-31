# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
subject="${args[--subject]}"
from="${args[--from]}"
to="${args[--to]}"
no_verdict="${args[--no-verdict]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

function is_file_side() {
    [[ "$1" == @* ]] || [ -f "$1" ]
}

registry_needed=0
for side in "$from" "$to"
do
    if [ -z "$side" ] || ! is_file_side "$side"
    then
        registry_needed=1
    fi
done
if [ $registry_needed -eq 1 ] && [[ ! -n "$subject" ]]
then
    for side in "$from" "$to"
    do
        if [[ -n "$side" ]] && ! is_file_side "$side" && [[ ! "$side" =~ ^id:[0-9]+$ ]]
        then
            logerror "❌ --subject is required to compare versions (or use id:<schema id> or @<file> for --from and --to)"
            exit 1
        fi
    done
    if [ -z "$from" ] || [ -z "$to" ]
    then
        logerror "❌ --subject is required when --from or --to is not set"
        exit 1
    fi
fi

registry_ok=0
if [ $registry_needed -eq 1 ] || [[ ! -n "$no_verdict" ]]
then
    get_sr_url_and_security
    if sr_request GET "/config"
    then
        registry_ok=1
    elif [ $registry_needed -eq 1 ]
    then
        logerror "❌ the Schema Registry is not reachable at ${sr_url}: $sr_error_message"
        exit 1
    fi
fi

encoded_subject=$(urlencode "$subject")

# defaults: --to the latest version, --from the version before it (or the latest one when --to is a file)
if [[ -n "$subject" ]] && { [ -z "$from" ] || [ -z "$to" ]; }
then
    sr_request GET "/subjects/${encoded_subject}/versions" || sr_exit_on_error "subject ${subject}"
    versions=$(echo "$sr_response" | jq -r '.[]')
    latest=$(echo "$versions" | tail -1)
    previous=$(echo "$versions" | tail -2 | head -1)
    if [ -z "$to" ]
    then
        to="$latest"
    fi
    if [ -z "$from" ]
    then
        if is_file_side "$to"
        then
            from="$latest"
        else
            from="$previous"
        fi
    fi
    if [ "$from" == "$to" ] && ! is_file_side "$to"
    then
        logerror "❌ subject ${subject} has only one version (${latest}): set --to @<file> to compare it with a file"
        exit 1
    fi
fi

# resolve one side to <prefix>.schema (the schema), <prefix>.type, <prefix>.label and <prefix>.body (request body)
function resolve_side() {
    local value="$1"
    local prefix="$2"
    local response
    if is_file_side "$value"
    then
        local file="${value#@}"
        if [ ! -f "$file" ]
        then
            logerror "❌ file $file not found"
            return 1
        fi
        cp "$file" "$prefix.schema"
        if ! sr_schema_request_body "$prefix.schema"
        then
            logerror "❌ no known schema could be identified in $file"
            return 1
        fi
        if echo "$sr_body" | jq -e '.references | length > 0' > /dev/null 2>&1
        then
            echo "$sr_body" | jq -r .schema > "$prefix.schema"
        fi
        echo "$sr_schema_type" > "$prefix.type"
        echo "$(basename "$file")" > "$prefix.label"
        echo "$sr_body" > "$prefix.body"
        return 0
    fi
    if [[ "$value" =~ ^id:([0-9]+)$ ]]
    then
        sr_request GET "/schemas/ids/${BASH_REMATCH[1]}" || { logerror "❌ schema id ${BASH_REMATCH[1]}: $sr_error_message"; return 1; }
        response="$sr_response"
        echo "id ${BASH_REMATCH[1]}" > "$prefix.label"
    else
        if [[ ! "$value" =~ ^([0-9]+|latest)$ ]]
        then
            logerror "❌ '$value' is not a version number, latest, id:<schema id> or @<file>"
            return 1
        fi
        sr_request GET "/subjects/${encoded_subject}/versions/${value}" || { logerror "❌ subject ${subject} version ${value}: $sr_error_message"; return 1; }
        response="$sr_response"
        echo "${subject} v$(echo "$response" | jq -r .version) (id $(echo "$response" | jq -r .id))" > "$prefix.label"
    fi
    echo "$response" | jq -r '.schemaType // "AVRO"' > "$prefix.type"
    if [ "$(cat "$prefix.type")" == "PROTOBUF" ]
    then
        echo "$response" | jq -r .schema > "$prefix.schema"
    else
        echo "$response" | jq -r .schema | jq . > "$prefix.schema"
    fi
    echo "$response" | jq -c '{schema, schemaType: (.schemaType // "AVRO"), references: (.references // [])}' > "$prefix.body"
    if echo "$response" | jq -e '(.references // []) | length > 0' > /dev/null
    then
        [[ -n "$json" ]] || logwarn "$(cat "$prefix.label") uses references: the referenced types are compared by name, not field by field"
    fi
}

resolve_side "$from" "$tmp_dir/from" || exit 1
resolve_side "$to" "$tmp_dir/to" || exit 1

verdict_args=()
if [[ ! -n "$no_verdict" ]]
then
    if [ $registry_ok -eq 1 ]
    then
        if [ "$(cat $tmp_dir/from.type)" == "$(cat $tmp_dir/to.type)" ]
        then
            if sr_compatibility_verdicts "$(cat $tmp_dir/from.body)" "$(cat $tmp_dir/to.body)" "$tmp_dir/verdicts.json"
            then
                verdict_args=(--verdicts "$tmp_dir/verdicts.json")
            fi
        fi
    else
        [[ -n "$json" ]] || logwarn "the Schema Registry is not reachable: no compatibility verdict (field-level diff only)"
    fi
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required by 'playground schema diff'"
    exit 1
fi
json_args=()
[[ -n "$json" ]] && json_args=(--json)
python3 -I "$root_folder/tools/schema-tool/schema_diff.py" \
    --left "$tmp_dir/from.schema" --left-type "$(cat $tmp_dir/from.type)" --left-label "$(cat $tmp_dir/from.label)" \
    --right "$tmp_dir/to.schema" --right-type "$(cat $tmp_dir/to.type)" --right-label "$(cat $tmp_dir/to.label)" \
    "${verdict_args[@]}" "${json_args[@]}"
