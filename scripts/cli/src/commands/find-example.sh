query="${args[query]}"
category="${args[--category]}"
limit="${args[--limit]}"
json="${args[--json]}"

if [ ${#other_args[@]} -gt 0 ]
then
    query="${query:+$query }${other_args[*]}"
fi

if [[ -n "${args[--browse]}" ]]
then
    if ! command -v python3 > /dev/null 2>&1
    then
        logerror "❌ python3 is required to build the examples explorer page"
        exit 1
    fi
    output_dir="${args[--output-dir]:-/tmp/playground-examples-explorer}"
    mkdir -p "$output_dir"
    log "🧭 Reading the examples of $root_folder"
    # with the pipeline builder next to it: the two pages link to each other
    if ! python3 -I "$root_folder/tools/pipeline-builder/catalog.py" pages --root "$root_folder" --output-dir "$output_dir" 2> "$output_dir/examples-explorer.log"
    then
        logerror "❌ could not build the examples explorer page:"
        cat "$output_dir/examples-explorer.log"
        exit 1
    fi
    report="$output_dir/examples-explorer.html"
    log "🔎 search, filter, pick an example, then copy its 'playground run' (or 'repro bootstrap') command"
    if [[ -z "$query" ]]
    then
        open_html_report "$report" "${args[--no-open]}"
        exit 0
    fi
    # the query prefills the search: a file:// url with the selection after #
    url="file://$report#q=$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote_plus(sys.argv[1]))' "$query")"
    log "✅ HTML report saved: $report"
    log "🔗 Open in browser: $url"
    if [[ -z "${args[--no-open]}" ]] && [[ -t 1 ]] && [ -z "$GITHUB_RUN_NUMBER" ]
    then
        open_url "$url" || true
    fi
    exit 0
fi

if [[ -z "$query" ]] && [[ -z "$category" ]]
then
    logerror "❌ give a query, or --category to list every example of a category"
    exit 1
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
    if [[ -z "$query" ]]
    then
        logwarn "❌ no example in category $category"
    else
        logwarn "❌ no example matches all the words of \"$query\"${category:+ in $category}"
    fi
    exit 1
fi

if [[ -z "$query" ]]
then
    log "🔎 examples of category $category"
else
    log "🔎 examples matching \"$query\"${category:+ in $category}, best first"
fi
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
