function listAllTags() { 
    local repo=${1} 
    local page_size=${2:-100} 
    [ -z "${repo}" ] && echo "Usage: listTags <repoName> [page_size]" 1>&2 && return 1 
    local base_url="https://registry.hub.docker.com/v2/repositories/${repo}/tags"
    local page=1 
    local res=$(curl "${base_url}?page_size=${page_size}&page=${page}" 2>/dev/null)
    echo ${res} | jq --raw-output '.results[].name' > /tmp/all_tags
    local tag_count=$(echo ${res} | jq '.count')
    ((page_count=(${tag_count}+${page_size}-1)/${page_size}))  # ceil(tag_count / page_size)
    for page in $(seq 2 $page_count); do
        curl "${base_url}?page_size=${page_size}&page=${page}" 2>/dev/null | jq --raw-output '.results[].name' >> /tmp/all_tags
    done
    cat /tmp/all_tags | sort
} 

listAllTags "confluentinc/cp-server-connect-base" | grep -v "ubi8" | grep -v "arm64" | grep -v "amd64" | grep -v "latest" | grep -v "deb8" > $root_folder/scripts/cli/tag-list.txt