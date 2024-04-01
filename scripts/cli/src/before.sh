## before hook
##
## Any code here will be placed inside a `before_hook()` function and called
## before running any command (but after processing its arguments).
##
## You can safely delete this file if you do not need it.

DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

vvv="${args[--vvv]}"
level="${args[--output-level]}"

if [[ -n "$vvv" ]]
then
    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        log "🐛 --vvv is set"
        export PS4='\[\033[0;36m\]🐞$(date "+%H:%M:%S")[$(basename $0):${LINENO}] \[\033[0m\]'
        set -x
        export PG_VERBOSE_MODE=true
    fi
fi

if [[ -n "$level" ]]
then
    export PG_LOG_LEVEL="$level"
    log "🔖 --output-level is set with $level"
fi