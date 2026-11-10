version=${args[--version]}

# repo:tag of the confluentinc images whose tag is exactly $1 (a grep would also match 7.4.10 for 7.4.1)
# by name, not by id: without -f, 'docker rmi <id>' refuses an image that has several tags
function cp_image_refs_with_tag () {
    docker image ls --format '{{.Repository}} {{.Tag}}' | awk -v v="$1" '$1 ~ /^confluentinc\// && $2 == v {print $1":"$2}' | sort -u
}

function remove_cp_images_with_tag () {
    local refs
    refs=$(cp_image_refs_with_tag "$1")
    if [ -z "$refs" ]
    then
        logwarn "no Confluent Platform docker image with tag $1"
        return
    fi
    # no -f: the engine refuses an image still used by a container instead of untagging it
    if ! docker rmi $refs
    then
        logwarn "⚠️ some images of $1 could not be removed (used by a container?)"
    fi
}

# tags of the confluentinc images used by a container, running or stopped (another session, a stopped environment)
in_use_tags=$(docker ps -a --format '{{.Image}}' | awk -F: '{sub(/^docker\.io\//, "", $1)} $1 ~ /^confluentinc\// && NF == 2 {print $2}' | sort -u)

function is_in_use () {
    echo "$in_use_tags" | grep -qxF "$1"
}

if [[ -n "$version" ]]
then
    if is_in_use "$version"
    then
        logerror "❌ Confluent Platform $version is used by a container, stop it first (playground stop, or docker ps -a)"
        exit 1
    fi
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

# TAG of the current run (--tag=x.y.z of the last playground run), kept so that re-run / container recreate do not pull it again
run_tag=$(playground state get run.array_flag_list_base64 2>/dev/null | base64 -d 2>/dev/null | grep -oE -- '--tag=[^" ]+' | head -1 | cut -d "=" -f 2)

all_versions=$(docker image ls --format '{{.Repository}} {{.Tag}}' | awk '$1 ~ /^confluentinc\// && $2 != "<none>" && $2 != "latest" && $2 != "2.0.0" {print $2}' | sort -u | sort -V)
versions=""
for v in $all_versions
do
    if [[ "$v" == "$LATEST_TAG" ]]
    then
        log "⏭️ $v kept: default TAG of the playground"
    elif [[ -n "$run_tag" && "$v" == "$run_tag" ]]
    then
        log "⏭️ $v kept: TAG of the current run"
    elif is_in_use "$v"
    then
        log "⏭️ $v kept: used by a container"
    else
        versions+="$v "
    fi
done

if [ -z "$versions" ]
then
    log "🧹 no Confluent Platform docker image to remove"
    exit 0
fi

remove_all=0
for version in $versions
do
    log "🧹 removing Confluent Platform docker images: $version"
    if [[ $remove_all -eq 0 && -z "$GITHUB_RUN_NUMBER" ]]
    then
        while true
        do
            # no answer can come (stdin closed: a script, an agent): use --version instead
            if ! read -r -p "Remove $version? [y]es / [n]o, skip it / [a]ll remaining / [q]uit: " choice
            then
                logerror "❌ no answer: stdin is closed, answer it in a terminal or use --version"
                exit 1
            fi
            case "$choice" in
                y|Y ) break;;
                n|N ) log "⏭️ $version skipped"; continue 2;;
                a|A ) remove_all=1; break;;
                q|Q ) exit 0;;
                * ) logwarn "invalid response <$choice>! Please enter y, n, a or q.";;
            esac
        done
    fi
    remove_cp_images_with_tag "$version"
done
