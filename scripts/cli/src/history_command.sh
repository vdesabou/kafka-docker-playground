DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

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

res=$(cat $root_folder/playground-run-history | sort -nr | uniq -u | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🏰" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer)

log "🚀 Are you sure you want to run:"
echo "$res"
check_if_continue
$res