subject="${args[--subject]}"
id="${args[--id]}"
deleted="${args[--deleted]}"
verbose="${args[--verbose]}"
store_in_tmp="${args[--store-in-tmp]}"

get_sr_url_and_security

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
#log "tmp_dir is $tmp_dir"

if [[ -n "$id" ]]
then
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $sr_security -s "${sr_url}/schemas/ids/${id}""
    fi

    curl_output=$(curl $sr_security -s "${sr_url}/schemas/ids/${id}")
    ret=$?
    if [ $ret -eq 0 ]
    then
        if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
        then
            error_code=$(echo "$curl_output" | jq -r .error_code)
            message=$(echo "$curl_output" | jq -r .message)
            logerror "❌ Command failed with error code $error_code"
            logerror "$message"
            exit 1
        else
            versions=$(curl $sr_security -s "${sr_url}/schemas/ids/${id}")
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi
    echo "$curl_output" | jq .
    exit 0
fi

if [[ ! -n "$subject" ]]
then
    log "✨ --subject flag was not provided, applying command to all subjects"
    if [[ -n "$deleted" ]]
    then
        subject=$(playground get-subject-list)
        echo "$subject" > $tmp_dir/subjects-all
        log "🧟 deleted subjects are included"
        subject=$(playground get-subject-list --deleted)
        echo "$subject" > $tmp_dir/subjects-deleted-tmp

        sort $tmp_dir/subjects-all $tmp_dir/subjects-deleted-tmp | uniq -u > $tmp_dir/subjects-deleted
    else
        subject=$(playground get-subject-list)
    fi
    if [ "$subject" == "" ]
    then
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
items=($subject)
for subject in ${items[@]}
do
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $sr_security -s "${sr_url}/subjects/${subject}/versions$maybe_include_deleted""
    fi

    curl_output=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions$maybe_include_deleted")
    ret=$?
    if [ $ret -eq 0 ]
    then
        if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
        then
            error_code=$(echo "$curl_output" | jq -r .error_code)
            message=$(echo "$curl_output" | jq -r .message)
            if [ "$error_code" == "40401" ]
            then
                continue
            fi
        else
            versions=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions$maybe_include_deleted")
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi

    for version in $(echo "${versions}" | jq -r '.[]')
    do
        schema_type=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}$maybe_include_deleted" | jq -r .schemaType)
        id=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}$maybe_include_deleted" | jq -r .id)
        case "${schema_type}" in
        JSON|AVRO|null)
            schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}/schema$maybe_include_deleted" | jq .)
        ;;
        PROTOBUF)
            schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}/schema$maybe_include_deleted")
        ;;
        esac

        if [ -f $tmp_dir/subjects-deleted ] && grep "${subject}" $tmp_dir/subjects-deleted
        then
            log "🧟 (deleted) subject ${subject} 💯 version ${version} (id $id)"
        else
            log "🔰 subject ${subject} 💯 version ${version} (id $id)"
        fi
        found=1

        if [[ -n "$verbose" ]]
        then
            log "🐞 curl command used"
            echo "curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}$maybe_include_deleted""
        fi
        echo "${schema}"

        if [[ -n "$store_in_tmp" ]] && [ "$store_in_tmp" != "" ]
        then
            echo "${schema}" > $store_in_tmp/schema_$id.txt
        fi
    done
done

if [[ -n "$subject" ]]
then
    if [ $found -eq 0 ]
    then
        logerror "❌ No schema found !"
        exit 1
    fi
fi