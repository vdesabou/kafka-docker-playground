DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

curl -s -S 'https://api.hub.confluent.io/api/plugins?per_page=100000' | jq '. | sort_by(.release_date) | reverse | .' > /tmp/allmanis.json

jq -r '.[] | "\(.owner.username)/\(.name)"' /tmp/allmanis.json | sort | uniq > $root_folder/scripts/cli/confluent-hub-plugin-list.txt

rm -f /tmp/allmanis.json