query="${args[query]}"
category="${args[--category]}"
limit="${args[--limit]}"
json="${args[--json]}"

if [ ${#other_args[@]} -gt 0 ]
then
    query="$query ${other_args[*]}"
fi

hits=$(find_examples "$query" "$limit" "$category")

if [[ -n "$json" ]]
then
    # one object per hit, fields in the order printed by find_examples
    if [ -z "$hits" ]
    then
        echo "[]"
        exit 1
    fi
    echo "$hits" | jq -R -s --arg root "$root_folder" '
        split("\n") | map(select(length > 0) | split("\t")) | map({
            script: ($root + "/" + .[1]),
            path: .[1],
            title: .[2],
            connector_classes: ((.[3] // "") | split(" ") | map(select(length > 0))),
            environment: (.[4] // ""),
            score: (.[0] | tonumber),
            run_command: ("playground run -f " + $root + "/" + .[1])
        })'
    exit 0
fi

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
