repo="confluentinc/cp-server-connect"
base_url="https://registry.hub.docker.com/v2/repositories/${repo}/tags"
page_size=100
# docker hub refuses anonymous requests beyond the first 1000 tags of a query ("pagination offset too large for
# anonymous requests"): the repository has more, so it is queried by version prefix, small enough to be paged entirely
max_anonymous_tags=1000

# appends to /tmp/all_tags the tags whose name contains <filter>, split into narrower filters if they are too many
function list_tags_matching () {
    local filter="$1"
    local res count page_count page
    res=$(curl -s "${base_url}?page_size=${page_size}&page=1&name=${filter}")
    count=$(echo "$res" | jq -r '.count // empty' 2> /dev/null)
    if [ -z "$count" ]
    then
        logwarn "could not list the tags of ${repo} matching ${filter}: $(echo "$res" | jq -r '.message // empty' 2> /dev/null | head -c 200)"
        return
    fi
    if [ "$count" -gt "$max_anonymous_tags" ]
    then
        for digit in 0 1 2 3 4 5 6 7 8 9
        do
            list_tags_matching "${filter}${digit}"
        done
        return
    fi
    echo "$res" | jq -r '.results[]?.name' >> /tmp/all_tags
    ((page_count=(count+page_size-1)/page_size))
    for page in $(seq 2 $page_count)
    do
        curl -s "${base_url}?page_size=${page_size}&page=${page}&name=${filter}" | jq -r '.results[]?.name' 2> /dev/null >> /tmp/all_tags
    done
}

rm -f /tmp/all_tags
touch /tmp/all_tags
# one query per major version (5.x onwards), until a major without tags
major=5
while true
do
    count=$(curl -s "${base_url}?page_size=1&name=${major}." | jq -r '.count // 0' 2> /dev/null)
    if [ "${count:-0}" -eq 0 ] && [ $major -gt 8 ]
    then
        break
    fi
    list_tags_matching "${major}."
    major=$((major+1))
done

# the filter matches anywhere in the name ("7." also matches 8.7.0): keep the tags of the major versions, without the
# os and architecture variants
grep -E '^[0-9]+\.' /tmp/all_tags | grep -v "ubi8" | grep -v "ubi9" | grep -v "arm64" | grep -v "amd64" | grep -v "s390x" | grep -v "latest" | grep -v "deb8" | sort -u | sort -V > /tmp/tmp_tags

if [ ! -s /tmp/tmp_tags ]
then
    logerror "❌ could not get the tag list of ${repo} from docker hub, keeping the current list"
    exit 1
fi

# one call per image instead of one docker image inspect per tag
docker image ls confluentinc/cp-schema-registry --format '{{.Tag}}' 2> /dev/null | sort -u > /tmp/installed_tags
docker image ls confluentinc/cp-server-connect --format '{{.Tag}}' 2> /dev/null | sort -u > /tmp/installed_connect_tags

# written aside then moved: the menu of playground run reads them while they are generated in the background
tmp_tag_list=$(mktemp)
tmp_connect_tag_list=$(mktemp)
for tag in $(cat /tmp/tmp_tags)
do
    if grep -qxF "${tag}" /tmp/installed_tags
    then
        echo "${tag} - already installed 💻" >> $tmp_tag_list
    else
        echo "${tag} - not installed, will be downloaded🛜" >> $tmp_tag_list
    fi

    if grep -qxF "${tag}" /tmp/installed_connect_tags
    then
        echo "${tag} - already installed 💻" >> $tmp_connect_tag_list
    else
        echo "${tag} - not installed, will be downloaded🛜" >> $tmp_connect_tag_list
    fi
done
mv -f $tmp_tag_list $root_folder/scripts/cli/tag-list.txt
mv -f $tmp_connect_tag_list $root_folder/scripts/cli/connect-tag-list.txt
