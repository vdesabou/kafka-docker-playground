file="${args[--file]}"
new_ids="${args[--new-ids]}"
on_conflict="${args[--on-conflict]}"
with_global_settings="${args[--with-global-settings]}"
subject_prefix="${args[--subject-prefix]}"
dry_run="${args[--dry-run]}"
verbose="${args[--verbose]}"

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required by 'playground schema import'"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
import_mode_subjects=()
function restore_modes() {
    local s
    for s in "${import_mode_subjects[@]}"
    do
        sr_request DELETE "/mode/$(urlencode "$s")" > /dev/null
    done
    rm -rf "$tmp_dir"
    return 0
}
trap restore_modes EXIT

input="$file"
case "$file" in
    *.tgz|*.tar.gz|*.zip)
        mkdir -p "$tmp_dir/extract"
        if [[ "$file" == *.zip ]]
        then
            unzip -q "$file" -d "$tmp_dir/extract" || exit 1
        else
            tar -xzf "$file" -C "$tmp_dir/extract" || exit 1
        fi
        manifest=$(find "$tmp_dir/extract" -name manifest.json | head -1)
        if [ -z "$manifest" ]
        then
            logerror "❌ no manifest.json in $file"
            exit 1
        fi
        input=$(dirname "$manifest")
        ;;
esac

plan_args=(plan --input "$input")
[[ -n "$subject_prefix" ]] && plan_args+=(--subject-prefix "$subject_prefix")
python3 -I "$root_folder/tools/schema-tool/schema_bundle.py" "${plan_args[@]}" > "$tmp_dir/plan.json" || exit 1
plan="$tmp_dir/plan.json"
nb_versions=$(jq '.versions | length' "$plan")
if [ "$nb_versions" == "0" ]
then
    logerror "❌ nothing to import from $file"
    exit 1
fi
log "📦 $(jq -r .format "$plan"): $(jq '.versions | map(.subject) | unique | length' "$plan") subject(s), ${nb_versions} version(s)"

get_sr_url_and_security
sr_request GET "/subjects" || sr_exit_on_error
existing=$(echo "$sr_response" | jq -r '.[]')

# subjects in the order of their first version (by id)
plan_subjects=$(jq -r '[.versions[].subject] | reduce .[] as $s ([]; if index([$s]) then . else . + [$s] end) | .[]' "$plan")
skipped=()
for subject in $plan_subjects
do
    action="create"
    if echo "$existing" | grep -qxF "$subject"
    then
        action="$on_conflict"
    fi
    versions_desc=$(jq -r --arg s "$subject" '[.versions[] | select(.subject == $s) | "v\(.version) id \(.id)"] | join(", ")' "$plan")
    case "$action" in
        create) icon="➕" ;;
        skip) icon="⏭️ (exists, skipped: --on-conflict overwrite or merge)"; skipped+=("$subject") ;;
        overwrite) icon="♻️ (exists, permanently deleted first)" ;;
        merge) icon="🔀 (exists, versions added)" ;;
    esac
    log "${icon} ${subject}: ${versions_desc}"
    if [[ -n "$dry_run" ]] || [ "$action" == "skip" ]
    then
        continue
    fi
    encoded_subject=$(urlencode "$subject")
    if [ "$action" == "overwrite" ]
    then
        sr_request DELETE "/subjects/${encoded_subject}" > /dev/null
        sr_request DELETE "/subjects/${encoded_subject}?permanent=true" || sr_exit_on_error "delete ${subject}"
    fi
    if [[ ! -n "$new_ids" ]]
    then
        maybe_force=""
        [ "$action" == "merge" ] && maybe_force="?force=true"
        if ! sr_request PUT "/mode/${encoded_subject}${maybe_force}" '{"mode": "IMPORT"}'
        then
            logerror "❌ the registry refused the IMPORT mode on ${subject}: $sr_error_code $sr_error_message"
            logerror "   it needs mode.mutability=true on the registry; or use --new-ids (the schemas get new ids)"
            exit 1
        fi
        import_mode_subjects+=("$subject")
    fi
done

if [[ -n "$dry_run" ]]
then
    log "🧪 dry run: nothing was imported"
    exit 0
fi

nb_ok=0
nb_errors=0
nb_skipped=0
while read -r entry
do
    subject=$(echo "$entry" | jq -r .subject)
    if [[ " ${skipped[*]} " == *" ${subject} "* ]]
    then
        nb_skipped=$((nb_skipped+1))
        continue
    fi
    if [[ -n "$new_ids" ]]
    then
        body=$(echo "$entry" | jq -c '{schema, schemaType, references} + (if .metadata then {metadata} else {} end) + (if .ruleSet then {ruleSet} else {} end)')
    else
        body=$(echo "$entry" | jq -c '{schema, schemaType, references, id, version} + (if .metadata then {metadata} else {} end) + (if .ruleSet then {ruleSet} else {} end)')
    fi
    if sr_request POST "/subjects/$(urlencode "$subject")/versions" "$body"
    then
        nb_ok=$((nb_ok+1))
        new_id=$(echo "$sr_response" | jq -r .id)
        old_id=$(echo "$entry" | jq -r .id)
        if [[ -n "$new_ids" ]] && [ "$new_id" != "$old_id" ]
        then
            log "   ⏺️ ${subject} v$(echo "$entry" | jq -r .version) → id ${new_id} (was ${old_id})"
        fi
    else
        nb_errors=$((nb_errors+1))
        logerror "❌ ${subject} v$(echo "$entry" | jq -r .version) (id $(echo "$entry" | jq -r .id)): $sr_error_code $sr_error_message"
        [ "$sr_error_code" == "42205" ] && logerror "   the id is already used by another schema in this registry: import in an empty registry, or use --new-ids"
    fi
done < <(jq -c '.versions[]' "$plan")

# back to the normal mode, then the subject settings of the source
for subject in "${import_mode_subjects[@]}"
do
    sr_request DELETE "/mode/$(urlencode "$subject")" > /dev/null
done
import_mode_subjects=()
for subject in $plan_subjects
do
    [[ " ${skipped[*]} " == *" ${subject} "* ]] && continue
    encoded_subject=$(urlencode "$subject")
    compatibility=$(jq -r --arg s "$subject" '.subjects[$s].compatibility // empty' "$plan")
    mode=$(jq -r --arg s "$subject" '.subjects[$s].mode // empty' "$plan")
    alias=$(jq -r --arg s "$subject" '.subjects[$s].alias // empty' "$plan")
    if [ -n "$compatibility" ]
    then
        sr_request PUT "/config/${encoded_subject}" "{\"compatibility\": \"$compatibility\"}" && log "   🛡️ ${subject}: compatibility ${compatibility}"
    fi
    if [ -n "$alias" ]
    then
        sr_request PUT "/config/${encoded_subject}" "{\"alias\": \"$alias\"}" && log "   🔯 ${subject}: alias of ${alias}"
    fi
    if [ -n "$mode" ] && [ "$mode" != "IMPORT" ] && [ "$mode" != "READWRITE" ]
    then
        sr_request PUT "/mode/${encoded_subject}" "{\"mode\": \"$mode\"}" && log "   🔏 ${subject}: mode ${mode}"
    fi
done
if [[ -n "$with_global_settings" ]]
then
    global_compatibility=$(jq -r '.global.compatibility // empty' "$plan")
    if [ -n "$global_compatibility" ]
    then
        sr_request PUT "/config" "{\"compatibility\": \"$global_compatibility\"}" && log "🌍 global compatibility ${global_compatibility}"
    fi
fi

if [ $nb_errors -gt 0 ]
then
    logerror "❌ ${nb_ok} version(s) imported, ${nb_errors} error(s), ${nb_skipped} skipped"
    exit 1
fi
if [[ -n "$new_ids" ]]
then
    log "✅ ${nb_ok} version(s) imported with new ids, ${nb_skipped} skipped: records written with the old ids won't decode here"
else
    log "✅ ${nb_ok} version(s) imported with their ids, ${nb_skipped} skipped: records written with them decode in this registry"
fi
