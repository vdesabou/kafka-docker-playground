version=${args[--version]}

# image ids of the confluentinc images whose tag is exactly $1 (a grep would also match 7.4.10 for 7.4.1)
function cp_image_ids_with_tag () {
    docker image ls --format '{{.Repository}} {{.Tag}} {{.ID}}' | awk -v v="$1" '$1 ~ /^confluentinc\// && $2 == v {print $3}' | sort -u
}

function remove_cp_images_with_tag () {
    local ids
    ids=$(cp_image_ids_with_tag "$1")
    if [ -z "$ids" ]
    then
        logwarn "no Confluent Platform docker image with tag $1"
        return
    fi
    docker rmi -f $ids
}

if [[ -n "$version" ]]
then
    log "🧹 removing Confluent Platform docker images: $version"
    check_if_continue
    remove_cp_images_with_tag "$version"
    exit 0
fi

LATEST_TAG=$(grep "# default tag" "$root_folder/scripts/utils.sh" | head -1 | cut -d "=" -f 2 | cut -d " " -f 1)
if [ -z "$LATEST_TAG" ]
then
    logerror "❌ error while getting default TAG "
    exit 1
fi

versions=$(docker image ls --format '{{.Repository}} {{.Tag}}' | awk -v d="$LATEST_TAG" '$1 ~ /^confluentinc\// && $2 != "<none>" && $2 != "latest" && $2 != "2.0.0" && $2 != d {print $2}' | sort -u)
if [ -z "$versions" ]
then
    log "🧹 no Confluent Platform docker image to remove (the default TAG $LATEST_TAG is always kept)"
    exit 0
fi
for version in $versions
do
    log "🧹 removing Confluent Platform docker images: $version (skipping default TAG $LATEST_TAG)"
    check_if_continue
    remove_cp_images_with_tag "$version"
done
