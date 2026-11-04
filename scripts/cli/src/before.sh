## before hook
##
## Any code here will be placed inside a `before_hook()` function and called
## before running any command (but after processing its arguments).
##
## You can safely delete this file if you do not need it.

DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

# a free file descriptor on stderr for the --verbose output of the kafka-* tools (see log_verbose_command): unlike stdout
# and stderr, $(...) and 2>&1 in the commands don't capture it.
# Only opened with --verbose: every child inherits it, even with '> file 2>&1 &', so a long-lived background process (the
# kubectl port-forward of cfk) would keep 'playground run … 2>&1 | tee' of run-tests.sh open forever
if [[ -n "${args[--verbose]}" ]]
then
    exec {playground_verbose_fd}>&2
fi

# --json: the log lines of this command go to stderr, stdout only holds the JSON result
# not exported: nested playground calls must keep their normal stdout (bashly validators and callers parse what they
# print with log); a --json command that runs nested commands sends their stdout to stderr itself (exec 3>&1 1>&2)
if [[ -n "${args[--json]}" ]]
then
    PG_LOG_TO_STDERR=1
fi

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
