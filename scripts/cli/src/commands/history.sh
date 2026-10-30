history_file="$root_folder/playground-run-history"
if [ ! -f "$history_file" ]
then
    logerror "❌ history could not be found !"
    logerror "$history_file does not exist"
    exit 1
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

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# most recent first, spaces normalized (so that a trailing space is not another entry), de-duplicated
tac "$history_file" | awk '{ gsub(/[ \t]+/, " "); sub(/^ /, ""); sub(/ $/, "") } /^playground run -f / && !seen[$0]++' > $tmp_dir/history

# one "<displayed line> TAB <line>" per entry whose script still exists: the root folder is not displayed,
# nor the credentials written in clear by older versions
nb_missing=0
: > $tmp_dir/entries
while IFS= read -r line
do
    # the script path ends at the first space that is not backslash-quoted
    script="${line#playground run -f }"
    script="${script//\\ /$'\x01'}"
    script="${script%% *}"
    script="${script//\\/}"
    if [ ! -f "${script//$'\x01'/ }" ]
    then
        nb_missing=$((nb_missing+1))
        continue
    fi
    displayed="${line//"$root_folder/"/}"
    if [[ "$displayed" == *"creds"* ]]
    then
        displayed=$(sed -E "s/(--cluster-(schema-registry-)?creds[ =])[^ ]+/\1'<masked>'/g" <<< "$displayed")
    fi
    printf '%s\t%s\n' "$displayed" "$line" >> $tmp_dir/entries
done < $tmp_dir/history

if [ $nb_missing -gt 0 ]
then
    log "🙈 $nb_missing entries not shown: their script no longer exists"
fi
if [ ! -s $tmp_dir/entries ]
then
    logerror "❌ no entry to replay in $history_file"
    exit 1
fi

res=$(cat $tmp_dir/entries | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🏰" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter $'\t' --with-nth 1 $fzf_option_wrap $fzf_option_pointer | cut -f 2-)
if [ -z "$res" ]
then
    exit 0
fi

# Prompt the user to edit the res variable
read -e -p "" -i "$res" edited_res

# Use the edited value if it is not empty
if [[ -n "$edited_res" ]]
then
  res="$edited_res"
fi

# the credentials are not kept in the history: take them from playground.ini if it is the same cluster
if [[ "$res" == *"'<masked>'"* ]]
then
    if [[ "$res" =~ --cluster-name[\ =]([^ ]+) ]] && [ "${BASH_REMATCH[1]}" == "$(playground state get ccloud.CLUSTER_NAME)" ]
    then
        res="${res//"--cluster-creds '<masked>'"/--cluster-creds $(printf '%q' "$(playground state get ccloud.CLUSTER_CREDS)")}"
        res="${res//"--cluster-schema-registry-creds '<masked>'"/--cluster-schema-registry-creds $(printf '%q' "$(playground state get ccloud.SCHEMA_REGISTRY_CREDS)")}"
    else
        logerror "❌ the credentials of this run are not kept in the history, and its cluster is not the one of playground.ini"
        logerror "👉 run it again and replace '<masked>' by the credentials"
        exit 1
    fi
fi

eval "$res"
