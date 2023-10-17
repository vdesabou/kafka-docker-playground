subject="${args[--subject]}"

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

if [[ ! -n "$subject" ]]
then
    log "✨ --subject flag was not provided, applying command to all subjects"
    subject=$(playground get-subject-list)
    if [ "$subject" == "" ]
    then
        logerror "❌ No subject found !"
        exit 1
    fi
fi

items=($subject)
for subject in ${items[@]}
do
    versions=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions")

    for version in $(echo "${versions}" | jq -r '.[]')
    do
        schema_type=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}"  | jq -r .schemaType)
        case "${schema_type}" in
        JSON|null)
            schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}/schema" | jq .)
        ;;
        PROTOBUF)
            schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}/schema")
        ;;
        esac

        log "🔰 subject ${subject} 💯 version ${version}"

        echo "${schema}"
    done
done