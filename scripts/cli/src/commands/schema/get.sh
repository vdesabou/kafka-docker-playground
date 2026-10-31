subject="${args[--subject]}"
id="${args[--id]}"
version="${args[--version]}"
deleted="${args[--deleted]}"
schema_only="${args[--schema-only]}"
json="${args[--json]}"
verbose="${args[--verbose]}"
store_in_tmp="${args[--store-in-tmp]}"

if [[ -n "$version" ]]
then
    if [[ ! -n "$subject" ]]
    then
        logerror "❌ --version is set without --subject being set"
        exit 1
    fi
    if [[ ! "$version" =~ ^([0-9]+|latest|-1)$ ]]
    then
        logerror "❌ --version must be a version number or latest"
        exit 1
    fi
fi
if [[ -n "$schema_only" ]] && [[ ! -n "$subject" ]] && [[ ! -n "$id" ]]
then
    logerror "❌ --schema-only needs --subject (latest version, or --version) or --id"
    exit 1
fi
if [[ -n "$schema_only" ]] && [[ -n "$json" ]]
then
    logerror "❌ --schema-only and --json are mutually exclusive"
    exit 1
fi

get_sr_url_and_security

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# print a schema string: avro and json schema pretty-printed, protobuf as is
function print_schema() {
    local schema_type="$1"
    local schema="$2"
    if [ "$schema_type" == "PROTOBUF" ]
    then
        echo "$schema"
    else
        echo "$schema" | jq . 2> /dev/null || echo "$schema"
    fi
}

if [[ -n "$id" ]]
then
    sr_request GET "/schemas/ids/${id}" || sr_exit_on_error
    if [[ -n "$schema_only" ]]
    then
        print_schema "$(echo "$sr_response" | jq -r '.schemaType // "AVRO"')" "$(echo "$sr_response" | jq -r .schema)"
    elif [[ -n "$json" ]]
    then
        response="$sr_response"
        subjects="[]"
        if sr_request GET "/schemas/ids/${id}/versions?deleted=true"
        then
            subjects="$sr_response"
        fi
        echo "$response" | jq --argjson id "$id" --argjson subjects "$subjects" '{id: $id, schemaType: (.schemaType // "AVRO")} + . + {subjects: $subjects}'
    else
        echo "$sr_response" | jq .
    fi
    exit 0
fi

if [[ -n "$schema_only" ]] && [[ ! -n "$version" ]]
then
    version="latest"
fi

if [[ ! -n "$subject" ]]
then
    [[ -n "$json" ]] || log "✨ --subject flag was not provided, applying command to all subjects"
    if [[ -n "$deleted" ]]
    then
        subject=$(playground get-subject-list)
        echo "$subject" > $tmp_dir/subjects-all
        [[ -n "$json" ]] || log "🧟 deleted subjects are included"
        subject=$(playground get-subject-list --deleted)
        echo "$subject" > $tmp_dir/subjects-deleted-tmp

        sort $tmp_dir/subjects-all $tmp_dir/subjects-deleted-tmp | uniq -u > $tmp_dir/subjects-deleted
    else
        subject=$(playground get-subject-list)
    fi
    if [ "$subject" == "" ]
    then
        if [[ -n "$json" ]]
        then
            echo "[]"
            exit 0
        fi
        logerror "❌ No subject found !"
        exit 1
    fi
fi

maybe_include_deleted=""
if [[ -n "$deleted" ]]
then
    maybe_include_deleted="?deleted=true"
fi

found=0
json_file=$tmp_dir/schemas.jsonl
: > $json_file
items=($subject)
for subject in ${items[@]}
do
    encoded_subject=$(urlencode "${subject}")
    if [[ -n "$version" ]]
    then
        versions="$version"
    else
        if ! sr_request GET "/subjects/${encoded_subject}/versions$maybe_include_deleted"
        then
            if [ "$sr_error_code" == "40401" ]
            then
                continue
            fi
            sr_exit_on_error
        fi
        versions=$(echo "${sr_response}" | jq -r '.[]')
    fi

    for v in $versions
    do
        if ! sr_request GET "/subjects/${encoded_subject}/versions/${v}$maybe_include_deleted"
        then
            if [ "$sr_error_code" == "40401" ] || [ "$sr_error_code" == "40402" ]
            then
                [[ -n "$version" ]] && sr_exit_on_error "subject ${subject}"
                continue
            fi
            sr_exit_on_error
        fi
        object="$sr_response"
        schema_type=$(echo "$object" | jq -r '.schemaType // "AVRO"')
        id=$(echo "$object" | jq -r .id)
        real_version=$(echo "$object" | jq -r .version)
        schema=$(echo "$object" | jq -r .schema)
        subject_deleted=false
        if [ -f $tmp_dir/subjects-deleted ] && grep -qx "${subject}" $tmp_dir/subjects-deleted
        then
            subject_deleted=true
        fi
        found=1

        if [[ -n "$schema_only" ]]
        then
            print_schema "$schema_type" "$schema"
            continue
        fi
        if [[ -n "$json" ]]
        then
            echo "$object" | jq -c --arg t "$schema_type" --argjson d "$subject_deleted" '. + {schemaType: $t, deleted: ((.deleted // false) or $d)}' >> $json_file
            continue
        fi

        if [ "$subject_deleted" == "true" ]
        then
            log "🧟 (deleted) subject ${subject} 💯 version ${real_version} (id $id)"
        else
            log "🔰 subject ${subject} 💯 version ${real_version} (id $id)"
        fi
        print_schema "$schema_type" "$schema"

        if [[ -n "$store_in_tmp" ]] && [ "$store_in_tmp" != "" ]
        then
            print_schema "$schema_type" "$schema" > $store_in_tmp/schema_$id.txt
        fi
    done
done

if [[ -n "$json" ]]
then
    jq -s . $json_file
    exit 0
fi

if [ $found -eq 0 ]
then
    logerror "❌ No schema found !"
    exit 1
fi
