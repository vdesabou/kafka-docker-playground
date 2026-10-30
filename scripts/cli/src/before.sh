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

# mdc-* environments: the cluster selected with --cluster is used by the nested playground calls too
if [[ -n "${args[--cluster]}" ]]
then
    export PLAYGROUND_CLUSTER="${args[--cluster]}"
elif [[ -z "$PLAYGROUND_CLUSTER" ]] && declare -f "playground_$(echo "$action" | tr ' -' '__')_usage" | grep -q -- "--cluster CLUSTER"
then
    # a command that takes --cluster: in an mdc-* environment, stop now when no cluster is selected (later, the
    # error of get_mdc_cluster can end up in the output of a tool captured by the command, like 'broker health')
    if is_mdc_environment
    then
        get_mdc_cluster
    fi
fi
