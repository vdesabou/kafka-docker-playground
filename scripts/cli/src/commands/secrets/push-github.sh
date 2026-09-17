profile="${args[--profile]:-$(get_active_secret_profile)}"
repo="${args[--repo]}"
only="${args[--only]:-all}"
push_as="${args[--as]:-auto}"
dry_run="${args[--dry-run]}"
force="${args[--force]}"

if ! command -v gh > /dev/null 2>&1
then
    logerror "❌ the GitHub CLI (gh) is not installed"
    logerror "👉 brew install gh"
    exit 1
fi

if ! gh auth status > /dev/null 2>&1
then
    logerror "❌ not logged in to GitHub"
    logerror "👉 gh auth login"
    exit 1
fi

#
# Always resolve the repository and pass it explicitly: a clone with several
# remotes (a fork plus the upstream) makes gh refuse to guess, and "pushed the
# secrets to the wrong repository" is not a mistake we want to make silently.
#
target="$repo"
if [ -z "$target" ]
then
    target=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
    if [ -z "$target" ]
    then
        logerror "❌ could not guess the repository from the current directory"
        logerror "👉 playground secrets push-github --repo <owner>/<repo>"
        exit 1
    fi
fi
repo_args=(--repo "$target")

names=$(secret_store_names "$profile")
if [ -z "$names" ]
then
    logerror "❌ profile $profile is empty, there is nothing to push"
    logerror "👉 playground secrets import --file <secret.properties>"
    exit 1
fi

#
# Resolving every value up front means a locked 1Password or an expired session
# fails before anything has been pushed, instead of halfway through.
#
secret_backend_ready || exit 1

#
# What the repository already has. Used to warn when a name is about to move
# from secrets.NAME to vars.NAME (or the reverse): GitHub keeps both, and the
# workflow that still reads the old one would silently get a stale value.
#
existing_secrets=" $(gh secret list "${repo_args[@]}" --json name --jq '.[].name' 2>/dev/null | tr '\n' ' ')"
existing_vars=" $(gh variable list "${repo_args[@]}" --json name --jq '.[].name' 2>/dev/null | tr '\n' ' ')"

to_push_secret=""
to_push_plain=""
nb_skipped=0
nb_moved=0

for name in $names
do
    location=$(secret_store_location "$name" "$profile" || true)
    if [ "$only" != "all" ] && [ "$location" != "$only" ]
    then
        continue
    fi

    #
    # GitHub only accepts [A-Za-z_][A-Za-z0-9_]* and reserves the GITHUB_
    # prefix. A rejected name is a hard error on gh's side, so filter it here
    # and keep going with the rest.
    #
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || [[ "$name" == GITHUB_* ]]
    then
        logwarn "⚠️ $name is not a valid GitHub secret name, skipped"
        nb_skipped=$((nb_skipped+1))
        continue
    fi

    #
    # The store is the source of truth here, not the shell. Say so loudly when
    # the two disagree: a leftover `source secret.properties` in the shell
    # profile is exactly how a rotation gets pushed with the old value.
    #
    if [ -n "${!name:-}" ] && [ "${!name}" != "$(secret_get_from_store "$name" "$profile" || true)" ]
    then
        logwarn "⚠️ \$$name is exported with a different value, the store wins"
    fi

    case "$push_as" in
        secret)   destination="secret" ;;
        variable) destination="variable" ;;
        *)
            if [ "$location" == "secret" ]
            then
                destination="secret"
            else
                destination="variable"
            fi
        ;;
    esac

    if [ "$destination" == "secret" ]
    then
        to_push_secret="${to_push_secret} ${name}"
        if [[ "$existing_vars" == *" ${name} "* ]]
        then
            nb_moved=$((nb_moved+1))
        fi
    else
        to_push_plain="${to_push_plain} ${name}"
        if [[ "$existing_secrets" == *" ${name} "* ]]
        then
            nb_moved=$((nb_moved+1))
        fi
    fi
done

if [ -z "$to_push_secret" ] && [ -z "$to_push_plain" ]
then
    logerror "❌ nothing to push for profile $profile (--only $only)"
    exit 1
fi

log "🐙 Pushing profile $profile to $target (--as $push_as)"
echo ""
for name in $to_push_secret
do
    if [[ "$existing_vars" == *" ${name} "* ]]
    then
        printf "  🔐 %-45s → secrets.%-45s ⚠️ vars.%s already exists\n" "$name" "$name" "$name"
    else
        printf "  🔐 %-45s → secrets.%s\n" "$name" "$name"
    fi
done
for name in $to_push_plain
do
    if [[ "$existing_secrets" == *" ${name} "* ]]
    then
        printf "  📝 %-45s → vars.%-45s ⚠️ secrets.%s already exists\n" "$name" "$name" "$name"
    else
        printf "  📝 %-45s → vars.%s\n" "$name" "$name"
    fi
done
echo ""

if [ $nb_moved -gt 0 ]
then
    logwarn "⚠️ $nb_moved name(s) already exist on the other side in $target"
    logwarn "⚠️ GitHub keeps both, so a workflow reading the old one would get a stale value"
    logwarn "👉 either use --as secret to keep everything where it is, or update the workflows and delete the leftovers"
fi

if [[ -n "$dry_run" ]]
then
    log "🔍 --dry-run, nothing was pushed"
    exit 0
fi

if [[ ! -n "$force" ]]
then
    logwarn "⚠️ this overwrites the existing secrets and variables of $target"
    check_if_continue
fi

nb_pushed=0
nb_failed=0

for name in $to_push_secret
do
    if ! value=$(secret_get_from_store "$name" "$profile")
    then
        logerror "❌ $name could not be resolved, skipped"
        nb_failed=$((nb_failed+1))
        continue
    fi
    # stdin, so the value never appears in `ps` nor in a file
    if printf '%s' "$value" | gh secret set "$name" "${repo_args[@]}" > /dev/null 2>&1
    then
        log "🔐 secrets.$name updated"
        nb_pushed=$((nb_pushed+1))
    else
        logerror "❌ could not set secrets.$name"
        nb_failed=$((nb_failed+1))
    fi
done

for name in $to_push_plain
do
    if ! value=$(secret_get_from_store "$name" "$profile")
    then
        logerror "❌ $name could not be resolved, skipped"
        nb_failed=$((nb_failed+1))
        continue
    fi
    if printf '%s' "$value" | gh variable set "$name" "${repo_args[@]}" > /dev/null 2>&1
    then
        log "📝 vars.$name=$value updated"
        nb_pushed=$((nb_pushed+1))
    else
        logerror "❌ could not set vars.$name"
        nb_failed=$((nb_failed+1))
    fi
done

echo ""
if [ $nb_failed -gt 0 ]
then
    logerror "❌ $nb_pushed pushed, $nb_failed failed"
    exit 1
fi

log "✅ $nb_pushed pushed to $target"
if [ $nb_skipped -gt 0 ]
then
    logwarn "⚠️ $nb_skipped skipped because of an invalid name"
fi
