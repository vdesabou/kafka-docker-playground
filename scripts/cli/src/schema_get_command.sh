subject="${args[--subject]}"
deleted="${args[--deleted]}"

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

if [[ ! -n "$subject" ]]
then
    log "✨ --subject flag was not provided, applying command to all subjects"
    if [[ -n "$deleted" ]]
    then
        subject=$(playground get-subject-list)
        echo "$subject" > /tmp/subjects-all
        log "🧟 deleted subjects are included"
        subject=$(playground get-subject-list --deleted)
        echo "$subject" > /tmp/subjects-deleted-tmp

        sort /tmp/subjects-all /tmp/subjects-deleted-tmp | uniq -u > /tmp/subjects-deleted
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

items=($subject)
for subject in ${items[@]}
do
    versions=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions$maybe_include_deleted")

    for version in $(echo "${versions}" | jq -r '.[]')
    do
        schema_type=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}$maybe_include_deleted" | jq -r .schemaType)
        id=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}$maybe_include_deleted" | jq -r .id)
        case "${schema_type}" in
        JSON|null)
            schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}/schema$maybe_include_deleted" | jq .)
        ;;
        PROTOBUF)
            schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}/schema$maybe_include_deleted")
        ;;
        esac

        if [ -f /tmp/subjects-deleted ] && grep "${subject}" /tmp/subjects-deleted
        then
            log "🧟 (deleted) subject ${subject} 💯 version ${version} (id $id)"
        else
            log "🔰 subject ${subject} 💯 version ${version} (id $id)"
        fi

        echo "${schema}"
    done
done