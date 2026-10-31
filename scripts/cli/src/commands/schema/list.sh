prefix="${args[--prefix]}"
deleted="${args[--deleted]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

sr_request GET "/subjects" || sr_exit_on_error
active_subjects=$(echo "$sr_response" | jq -r '.[]')
subjects="$active_subjects"
if [[ -n "$deleted" ]]
then
    sr_request GET "/subjects?deleted=true" || sr_exit_on_error
    subjects=$(echo "$sr_response" | jq -r '.[]')
fi

global_compatibility="BACKWARD"
if sr_request GET "/config"
then
    global_compatibility=$(echo "$sr_response" | jq -r '.compatibilityLevel // .compatibility')
fi
global_mode="READWRITE"
if sr_request GET "/mode"
then
    global_mode=$(echo "$sr_response" | jq -r '.mode')
fi

rows_file=$(mktemp -t pg-XXXXXXXXXX)
trap 'rm -f $rows_file' EXIT
for subject in $subjects
do
    if [ -n "$prefix" ] && [[ "$subject" != "$prefix"* ]]
    then
        continue
    fi
    encoded_subject=$(urlencode "$subject")
    is_deleted=true
    maybe_deleted="?deleted=true"
    if echo "$active_subjects" | grep -qxF "$subject"
    then
        is_deleted=false
        maybe_deleted=""
    fi
    sr_request GET "/subjects/${encoded_subject}/versions${maybe_deleted}" || continue
    versions=$(echo "$sr_response" | jq -c '.')
    latest_version=$(echo "$versions" | jq -r 'max')
    sr_request GET "/subjects/${encoded_subject}/versions/${latest_version}${maybe_deleted}" || continue
    latest_id=$(echo "$sr_response" | jq -r '.id')
    schema_type=$(echo "$sr_response" | jq -r '.schemaType // "AVRO"')

    compatibility="$global_compatibility"
    compatibility_source="global"
    if sr_request GET "/config/${encoded_subject}"
    then
        compatibility=$(echo "$sr_response" | jq -r '.compatibilityLevel // .compatibility')
        compatibility_source="subject"
    fi
    mode="$global_mode"
    mode_source="global"
    if sr_request GET "/mode/${encoded_subject}"
    then
        mode=$(echo "$sr_response" | jq -r '.mode')
        mode_source="subject"
    fi
    jq -cn --arg subject "$subject" --argjson versions "$versions" --argjson latest_version "$latest_version" \
        --argjson latest_id "$latest_id" --arg schema_type "$schema_type" --arg compatibility "$compatibility" \
        --arg compatibility_source "$compatibility_source" --arg mode "$mode" --arg mode_source "$mode_source" \
        --argjson deleted "$is_deleted" \
        '{subject: $subject, versions: $versions, latest_version: $latest_version, latest_id: $latest_id, schema_type: $schema_type, compatibility: $compatibility, compatibility_source: $compatibility_source, mode: $mode, mode_source: $mode_source, deleted: $deleted}' >> $rows_file
done

if [[ -n "$json" ]]
then
    jq -s '{global_compatibility: "'"$global_compatibility"'", global_mode: "'"$global_mode"'", subjects: .}' $rows_file
    exit 0
fi

if [ ! -s $rows_file ]
then
    logwarn "no subject found${prefix:+ with prefix $prefix}"
    exit 0
fi

log "🔰 Subjects (🌍 = inherited from the global setting of the registry: compatibility $global_compatibility, mode $global_mode)"
{
    echo -e "SUBJECT\tVERSIONS\tLATEST\tID\tTYPE\tCOMPATIBILITY\tMODE"
    jq -r '[ (if .deleted then "🧟 " else "" end) + .subject,
             (.versions | length | tostring),
             ("v" + (.latest_version | tostring)),
             (.latest_id | tostring),
             .schema_type,
             .compatibility + (if .compatibility_source == "global" then " 🌍" else "" end),
             .mode + (if .mode_source == "global" then " 🌍" else "" end) ] | @tsv' $rows_file
} | column -t -s $'\t'
