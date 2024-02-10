## before hook
##
## Any code here will be placed inside a `before_hook()` function and called
## before running any command (but after processing its arguments).
##
## You can safely delete this file if you do not need it.

DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

verbose="${args[--verbose]}"

if [[ -n "$verbose" ]]
then
    log "🐛 --verbose is set"
    export PS4='\[\033[0;35m\]+ $(date "+%Y-%m-%d %H:%M:%S") [debug] \[\033[0m\]'
    set -x 
fi