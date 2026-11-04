connector="${args[--connector]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "❌ connector select-config command is not supported with $connector_type connector"
    exit 1
fi

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

log "🗜️ Easily select config from all possible configuration parameters"
log "🎓 Tip: use <tab> to select multiple config at once, then press <enter> to confirm"

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    json_file=$(playground connector show-config-parameters --only-show-json --only-show-json-file-path --connector $connector)
    if [ ! -f "$json_file" ]
    then
        logwarn "❌ file <$json_file> does not exist, could not retrieve json config file for connector $connector."
        exit 1
    fi

    fzf_version=$(get_fzf_version)
    if version_gt $fzf_version "0.38"
    then
        fzf_option_wrap="--preview-window=40%,wrap"
        fzf_option_pointer="--pointer=👉"
        fzf_option_rounded="--border=rounded"
    else
        fzf_option_wrap=""
        fzf_option_pointer=""
        fzf_option_rounded=""
    fi

    set +e
    res=$(cat $json_file | fzf --multi --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🗜️" --header="<enter> to confirm, <esc> to cancel" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)

    set -e
    if [ -z "$res" ]
    then
        # <esc>: nothing selected, the clipboard is left as it is
        log "💤 no config parameter selected for connector $connector"
        continue
    fi

    log "🗜️ selected config parameter(s) for connector $connector"
    echo "$res"

    if [[ "$OSTYPE" == "darwin"* ]]
    then
        clipboard=$(playground config get clipboard)
        if [ "$clipboard" == "" ]
        then
            playground config set clipboard true
        fi

        if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
        then
            echo "$res" > "$tmp_dir/selected-$connector"
            pbcopy < "$tmp_dir/selected-$connector"
            log "📋 config has been copied to the clipboard (disable with 'playground config clipboard false')"
        fi
    fi
done