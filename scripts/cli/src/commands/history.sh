if [ ! -f $root_folder/playground-run-history ]
then
    logerror "❌ history could not be found !"
    logerror "$root_folder/playground-run-history does not exist"
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

awk '!seen[$0]++' $root_folder/playground-run-history > /tmp/tmp
res=$(tac /tmp/tmp| sed '/^$/d' | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🏰" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter "kafka-docker-playground" --with-nth "2,3,4" $fzf_option_wrap $fzf_option_pointer)

# Prompt the user to edit the res variable
read -e -p "" -i "$res" edited_res

# Use the edited value if it is not empty
if [[ -n "$edited_res" ]]; then
  res="$edited_res"
fi

# log "🚀 Are you sure you want to run:"
# echo "$res"
#check_if_continue
$res