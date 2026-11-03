query="${args[query]}"
limit="${args[--limit]}"
json="${args[--json]}"

if [ ${#other_args[@]} -gt 0 ]
then
    query="$query ${other_args[*]}"
fi

hits=$(find_commands "$query" "$limit")

if [[ -n "$json" ]]
then
    if [ -z "$hits" ]
    then
        echo "[]"
        exit 1
    fi
    echo "$hits" | jq -R -s '
        split("\n") | map(select(length > 0) | split("\u001f")) | map({
            command: ("playground " + .[1]),
            matched: .[2],
            usage: (.[3] // ""),
            deep_dive: (.[4] // ""),
            source: (.[5] // ""),
            score: (.[0] | tonumber),
            help_command: ("playground " + .[1] + " --help")
        })'
    exit 0
fi

if [ -z "$hits" ]
then
    logwarn "❌ no command matches \"$query\""
    log "🎓 try other words, browse https://kafka-docker-playground.io/#/which-command or run playground --help"
    exit 1
fi

log "🧭 commands matching \"$query\", best first"
while IFS=$'\037' read -r score command matched usage url source
do
    echo ""
    echo "playground $command"
    if [[ -n "$matched" ]]
    then
        echo "    ❓ ${matched//\`/}"
    fi
    if [[ -n "$usage" ]]
    then
        echo "    👉 ${usage//\`/}"
    fi
    if [[ -n "$url" ]]
    then
        echo "    🍪 $url"
    fi
done <<< "$hits"
echo ""
log "🎓 playground <command> --help shows every flag and an example output"
