test_file="${args[--file]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"
all="${args[--all]}"
force="${args[--force]}"

#
# stdout carries shell code that the caller sources, so every message this
# command prints has to go to stderr. A stray log line on stdout would not be
# displayed, it would be executed.
#

if [ -t 1 ] && [[ ! -n "$force" ]]
then
    logerror "❌ stdout is a terminal, every value would be printed in clear on screen" >&2
    logerror "👉 source <(playground secrets env)" >&2
    logerror "🎓 --force prints them anyway" >&2
    exit 1
fi

if [[ -n "$all" ]]
then
    names=$(secret_store_names "$profile")
    what="profile $profile"
else
    if [[ ! -n "$test_file" ]]
    then
        test_file=$(playground state get run.test_file)
        if [ -z "$test_file" ]
        then
            logerror "❌ no example specified and no example was ran before" >&2
            logerror "👉 playground secrets env -f <example>" >&2
            exit 1
        fi
    fi

    if [[ $test_file == *"@"* ]]
    then
        test_file=${test_file#*@}
    fi

    if [ ! -f "$test_file" ]
    then
        logerror "❌ $test_file does not exist" >&2
        exit 1
    fi

    names=$(get_mandatory_env_vars "$test_file")
    what="$(basename "$test_file")"
fi

if [ -z "$names" ]
then
    log "💤 $what does not require any environment variable" >&2
    exit 0
fi

# fail before printing half of the exports if the backend is locked
secret_backend_ready >&2 || exit 1

#
# Resolve everything in one parallel batch. Sourcing this is on the critical
# path of an interactive shell, and one sequential backend round trip per
# variable is what makes it feel slow.
#
secret_prefetch "$profile" $names 2> /dev/null

nb=0
nb_missing=0
missing=""
for name in $names
do
    #
    # secret_get and not secret_get_from_store: an exported value wins here, the
    # same way it does when an example runs. Someone who exported a variable on
    # purpose should not have it silently replaced.
    #
    if value=$(secret_get "$name" "$profile")
    then
        #
        # single quoted, so nothing in the value is interpreted by the shell
        # that sources this
        #
        printf 'export '
        secret_shell_assignment "$name" "$value"
        nb=$((nb+1))
    else
        missing="${missing} ${name}"
        nb_missing=$((nb_missing+1))
    fi
done

if [ $nb -gt 0 ]
then
    log "🔐 $nb variable(s) exported for $what (profile $profile)" >&2
fi

if [ $nb_missing -gt 0 ]
then
    #
    # Only now is it worth paying for the vault round trip: it turns a
    # misleading "missing from the store" into the real reason when the whole
    # vault is the problem.
    #
    secret_backend_vault_ready >&2 || exit 1
    logwarn "⚠️ not exported, missing from the store:${missing}" >&2
    logwarn "👉 playground secrets set <name>" >&2
fi
