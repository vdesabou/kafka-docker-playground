subject="${args[--subject]}"
schema="${args[--schema]}"
version="${args[--version]}"
compatibility="${args[--compatibility]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

# exit codes: 0 compatible, 1 not compatible, 2 the check could not be done
if [[ -n "$version" ]] && [[ ! "$version" =~ ^([0-9]+|latest)$ ]]
then
    logerror "❌ --version must be a version number or latest"
    exit 2
fi

get_sr_url_and_security

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
schema_file=$tmp_dir/schema
sr_read_schema_arg "$schema" "$schema_file" || exit 2
if ! sr_schema_request_body "$schema_file"
then
    logerror "❌ no known schema could be identified"
    exit 2
fi
body="$sr_body"
encoded_subject=$(urlencode "$subject")

# the rule in force on the subject
if sr_request GET "/config/${encoded_subject}"
then
    subject_rule=$(echo "$sr_response" | jq -r '.compatibilityLevel // .compatibility')
    subject_rule_source="subject"
else
    sr_request GET "/config" || sr_exit_on_error
    subject_rule=$(echo "$sr_response" | jq -r '.compatibilityLevel // .compatibility')
    subject_rule_source="global"
fi

# what the new schema is checked against: one version, or what the rule says (the latest version, all of them with *_TRANSITIVE)
if [[ -n "$version" ]]
then
    against="version ${version}"
    check_path_suffix="/versions/${version}?verbose=true"
else
    against="the versions the rule checks"
    check_path_suffix="/versions?verbose=true"
fi

rule="$subject_rule"
rule_source="$subject_rule_source"
check_subject="$encoded_subject"
tmp_subject=""
function cleanup_tmp_subject() {
    if [ -n "$tmp_subject" ]
    then
        sr_request DELETE "/config/${tmp_subject}" > /dev/null
        sr_request DELETE "/subjects/${tmp_subject}" > /dev/null
        sr_request DELETE "/subjects/${tmp_subject}?permanent=true" > /dev/null
    fi
    rm -rf $tmp_dir
    # the status of the last command of an EXIT trap would become the exit code of the command
    return 0
}

if [[ -n "$compatibility" ]] && [ "$compatibility" != "$subject_rule" ]
then
    # another rule than the subject's: copy its versions to a temporary subject with that rule (same schemas, so same ids)
    rule="$compatibility"
    rule_source="--compatibility"
    if sr_request GET "/subjects/${encoded_subject}/versions"
    then
        versions=$(echo "$sr_response" | jq -r '.[]')
        tmp_subject="playground-schema-check-$$-$RANDOM"
        trap cleanup_tmp_subject EXIT
        sr_request PUT "/config/${tmp_subject}" '{"compatibility": "NONE"}' || sr_exit_on_error "temporary subject"
        for v in $versions
        do
            if [[ -n "$version" ]] && [ "$version" != "latest" ] && [ "$v" -gt "$version" ]
            then
                break
            fi
            sr_request GET "/subjects/${encoded_subject}/versions/${v}" || sr_exit_on_error
            copy_body=$(echo "$sr_response" | jq -c '{schema, schemaType: (.schemaType // "AVRO"), references: (.references // [])}')
            sr_request POST "/subjects/${tmp_subject}/versions" "$copy_body" || { logerror "❌ can't copy version ${v} to the temporary subject: $sr_error_message"; exit 2; }
        done
        sr_request PUT "/config/${tmp_subject}" "{\"compatibility\": \"$rule\"}" || sr_exit_on_error "temporary subject"
        check_subject="$tmp_subject"
        if [[ -n "$version" ]]
        then
            check_path_suffix="/versions/latest?verbose=true"
        fi
    fi
fi

compatible=""
messages="[]"
if sr_request POST "/compatibility/subjects/${check_subject}${check_path_suffix}" "$body"
then
    compatible=$(echo "$sr_response" | jq -r '.is_compatible')
    messages=$(echo "$sr_response" | jq -c '.messages // []')
    invalid=$(echo "$messages" | jq -r '.[] | select(startswith("Invalid schema"))' | head -1)
    if [ "$compatible" != "true" ] && [ -n "$invalid" ]
    then
        if [[ -n "$json" ]]
        then
            jq -n --arg s "$subject" --arg m "$invalid" '{subject: $s, compatible: null, error_code: "invalid-schema", message: $m}'
            exit 2
        fi
        logerror "❌ the schema itself is invalid (register would refuse it too, 42201)"
        logerror "$(echo "$invalid" | sed -e 's/.*details: //')"
        exit 2
    fi
else
    case "$sr_error_code" in
        40401)
            # no version yet: the first version is always accepted
            compatible="true"
            against="nothing (subject ${subject} has no version yet, the first version is always accepted)"
            ;;
        *)
            if [[ -n "$json" ]]
            then
                jq -n --arg s "$subject" --arg code "$sr_error_code" --arg m "$sr_error_message" '{subject: $s, compatible: null, error_code: $code, message: $m}'
                exit 2
            fi
            logerror "❌ the registry could not check the schema: error code $sr_error_code"
            logerror "$sr_error_message"
            [ "$sr_error_code" == "42201" ] && logerror "   the schema itself is invalid (it would be refused by register too)"
            exit 2
            ;;
    esac
fi

if [[ -n "$json" ]]
then
    jq -n --arg s "$subject" --arg against "$against" --arg rule "$rule" --arg source "$rule_source" \
        --argjson compatible "$compatible" --argjson messages "$messages" --arg type "$sr_schema_type" \
        '{subject: $s, schema_type: $type, against: $against, compatibility: $rule, compatibility_source: $source, compatible: $compatible, messages: $messages}'
else
    if [ "$compatible" == "true" ]
    then
        log "✅ the schema is compatible with ${against} of ${subject} under ${rule} (${rule_source} rule): register would accept it"
    else
        logerror "❌ the schema is not compatible with ${against} of ${subject} under ${rule} (${rule_source} rule): register would refuse it (40901)"
        sr_format_compatibility_messages "$messages"
    fi
    if [ "$rule_source" != "--compatibility" ] && [ "$rule" != "NONE" ]
    then
        log "🎓 nothing was registered. --compatibility <rule> evaluates it under another rule, 'playground schema diff --subject ${subject} --to @<file>' shows what changed"
    fi
fi

if [ "$compatible" == "true" ]
then
    exit 0
fi
exit 1
