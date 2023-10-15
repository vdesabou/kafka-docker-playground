ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

curl $sr_security -s "${sr_url}/subjects" | jq -r '.[]'