name="${args[name]}"
value="${args[--value]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"

force=""
if [[ -n "${args[--secret]}" ]]
then
    force="secret"
elif [[ -n "${args[--plain]}" ]]
then
    force="plain"
fi

if [ "$force" == "secret" ] || { [ -z "$force" ] && is_secret_env_var_name "$name"; }
then
    secret_backend_writable || exit 1
fi

if [[ ! -n "$value" ]]
then
    value=$(read_secret_value_interactively "$name") || exit 1
fi

secret_store_value "$name" "$value" "$profile" "$force"

#
# 🐙 Keep the GitHub Actions configuration in sync, for whoever maintains the
# repository the workflows run in.
#
# Opt in through a config key rather than a hardcoded username: `whoami` is the
# same on the ec2 playground instances, where gh is usually not authenticated,
# and an explicit OWNER/REPO means a clone of a fork can never be written to by
# accident (push-github otherwise guesses the target from the remote).
#
#   playground config set secrets.github-repo vdesabou/kafka-docker-playground
#
# Hooked here and not in secret_store_value(): `secrets import` would fire one
# gh call per line, and the "save this for next time" menu of `playground run`
# would quietly publish to GitHub.
#
github_repo=$(playground config get secrets.github-repo 2> /dev/null)
if [ -n "$github_repo" ] && [ -z "$GITHUB_RUN_NUMBER" ] && command -v gh > /dev/null 2>&1
then
    #
    # Never fail `secrets set` on this: the value is already stored and rotated
    # by now, and losing that outcome over an expired gh token would be absurd.
    #
    if ! playground secrets push-github "$name" --repo "$github_repo" --profile "$profile"
    then
        logwarn "⚠️ $name was stored but could not be pushed to $github_repo"
        logwarn "👉 playground secrets push-github $name"
    fi
fi
