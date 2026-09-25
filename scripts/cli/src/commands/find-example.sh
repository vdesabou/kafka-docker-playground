query="${args[query]}"
category="${args[--category]}"
limit="${args[--limit]}"

if [ ${#other_args[@]} -gt 0 ]
then
    query="$query ${other_args[*]}"
fi

hits=$(find_examples "$query" "$limit" "$category")

if [ -z "$hits" ]
then
    logwarn "❌ no example matches all the words of \"$query\"${category:+ in $category/}"
    exit 1
fi

log "🔎 examples matching \"$query\"${category:+ in $category/}, best first"
while IFS=$'\t' read -r score script title classes environment
do
    details="$title"
    if [[ -n "$classes" ]]
    then
        details="${details:+$details · }$classes"
    fi
    if [[ -n "$environment" ]]
    then
        details="${details:+$details · }$environment"
    fi
    echo "playground run -f $root_folder/$script"
    if [[ -n "$details" ]]
    then
        echo "    ${details}"
    fi
done <<< "$hits"
