connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

log "🗜️ Easily select config from all possible configuration parameters"
log "🎓 Tip: use <tab> to select multiple config at once !"

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
    for connector in ${items[@]}
    do

    json_file=$(playground connector show-config-parameters --only-show-json --only-show-json-file-path --connector $connector)
    if [ ! -f $json_file ]
    then
        logwarn "❌ file $json_file does not exist, could not retrieve json config file for connector $connector."
    fi

    fzf_version=$(get_fzf_version)
    if version_gt $fzf_version "0.38"
    then
        fzf_option_wrap="--preview-window=40%,wrap"
        fzf_option_pointer="--pointer=👉"
        fzf_option_rounded="--border=rounded"
    else
        fzf_options=""
        fzf_option_pointer=""
        fzf_option_rounded=""
    fi

    res=$(cat $json_file | fzf --multi --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🗜️" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)

    log "🗜️ selected config parameter for connector $connector"
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
            tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
            trap 'rm -rf $tmp_dir' EXIT
            echo "$res" > $tmp_dir/tmp

            cat $tmp_dir/tmp | pbcopy
            log "📋 config parameter has been copied to the clipboard (disable with 'playground config set clipboard false')"
        fi
    fi
done