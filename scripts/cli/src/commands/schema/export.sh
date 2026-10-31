subject_prefix="${args[--subject-prefix]}"
output_dir="${args[--output-dir]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

sr_request GET "/subjects" || sr_exit_on_error
subjects=$(echo "$sr_response" | jq -r '.[]')
if [ -n "$subject_prefix" ]
then
    subjects=$(echo "$subjects" | grep -F "$subject_prefix" | awk -v p="$subject_prefix" 'index($0, p) == 1')
fi
if [ -z "$subjects" ]
then
    logerror "❌ no subject to export${subject_prefix:+ with prefix $subject_prefix}"
    exit 1
fi

mkdir -p "$output_dir" || exit 1
global_compatibility=null
sr_request GET "/config" && global_compatibility=$(echo "$sr_response" | jq '.compatibilityLevel // .compatibility')
global_mode=null
sr_request GET "/mode" && global_mode=$(echo "$sr_response" | jq '.mode')

subjects_file=$(mktemp -t pg-XXXXXXXXXX)
trap 'rm -f $subjects_file' EXIT
nb_versions=0
nb_subjects=0
for subject in $subjects
do
    encoded_subject=$(urlencode "$subject")
    # one folder per subject (characters that are not safe in a file name replaced by _)
    folder=$(echo "$subject" | sed -e 's#[/:\\ *?"<>|]#_#g')
    mkdir -p "$output_dir/$folder"
    sr_request GET "/subjects/${encoded_subject}/versions" || continue
    versions_json="[]"
    for v in $(echo "$sr_response" | jq -r '.[]')
    do
        sr_request GET "/subjects/${encoded_subject}/versions/${v}" || continue
        obj="$sr_response"
        schema_type=$(echo "$obj" | jq -r '.schemaType // "AVRO"')
        case "$schema_type" in
            PROTOBUF) ext=proto ;;
            JSON) ext=json ;;
            *) ext=avsc ;;
        esac
        file="$folder/v${v}.${ext}"
        if [ "$schema_type" == "PROTOBUF" ]
        then
            echo "$obj" | jq -r .schema > "$output_dir/$file"
        else
            echo "$obj" | jq -r .schema | jq . > "$output_dir/$file"
        fi
        versions_json=$(echo "$versions_json" | jq --argjson o "$obj" --arg file "$file" --arg t "$schema_type" \
            '. + [{version: $o.version, id: $o.id, schemaType: $t, file: $file, references: ($o.references // []), metadata: ($o.metadata // null), ruleSet: ($o.ruleSet // null)}]')
        nb_versions=$((nb_versions+1))
    done
    compatibility=null
    alias=null
    if sr_request GET "/config/${encoded_subject}"
    then
        compatibility=$(echo "$sr_response" | jq '.compatibilityLevel // .compatibility // null')
        alias=$(echo "$sr_response" | jq '.alias // null')
    fi
    mode=null
    sr_request GET "/mode/${encoded_subject}" && mode=$(echo "$sr_response" | jq '.mode')
    jq -cn --arg s "$subject" --argjson c "$compatibility" --argjson m "$mode" --argjson a "$alias" --argjson v "$versions_json" \
        '{subject: $s, compatibility: $c, mode: $m, alias: $a, versions: $v}' >> "$subjects_file"
    nb_subjects=$((nb_subjects+1))
    log "📦 ${subject}: $(echo "$versions_json" | jq 'length') version(s)"
done

jq -s --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg url "$sr_url" --argjson gc "$global_compatibility" --argjson gm "$global_mode" \
    '{exported_at: $date, registry: $url, global: {compatibility: $gc, mode: $gm}, subjects: .}' "$subjects_file" > "$output_dir/manifest.json"

log "✅ ${nb_subjects} subject(s), ${nb_versions} version(s) exported to ${output_dir} (manifest.json + one file per version)"
log "🎓 to load them in another registry with the same ids: playground schema import -f ${output_dir}"
