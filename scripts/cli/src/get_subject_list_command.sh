get_sr_url_and_security
deleted="${args[--deleted]}"

if [[ -n "$deleted" ]]
then
    curl $sr_security -s "${sr_url}/subjects?deleted=true" | jq -r '.[]'
else
    curl $sr_security -s "${sr_url}/subjects" | jq -r '.[]'
fi