subject="${args[--subject]}"
deleted="${args[--deleted]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
#log "tmp_dir is $tmp_dir"

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