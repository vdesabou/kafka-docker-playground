ret=$(get_sr_url_and_security)
deleted="${args[--deleted]}"

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

if [[ -n "$deleted" ]]
then
    curl $sr_security -s "${sr_url}/subjects?deleted=true" | jq -r '.[]'
else
    curl $sr_security -s "${sr_url}/subjects" | jq -r '.[]'
fi