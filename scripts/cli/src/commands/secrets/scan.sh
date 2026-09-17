staged="${args[--staged]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"

cd "$root_folder"

names=$(secret_store_names "$profile")
if [ -z "$names" ]
then
    log "🔐 No secret stored in profile $profile, nothing to scan for"
    exit 0
fi

if [[ -n "$staged" ]]
then
    log "🔎 Scanning the staged diff for values of profile $profile"
    haystack=$(git diff --staged)
else
    log "🔎 Scanning the working tree for values of profile $profile"
    haystack=""
fi

nb_leaks=0

for name in $names
do
    # plain variables are not sensitive, a bucket name or a region is expected
    # to appear in the examples
    [ "$(secret_store_location "$name" "$profile" || true)" == "secret" ] || continue

    value=$(secret_get "$name" "$profile") || continue
    # too short to be searched for without a flood of false positives
    [ ${#value} -lt 8 ] && continue

    if [[ -n "$staged" ]]
    then
        if printf '%s' "$haystack" | grep -qF -- "$value"
        then
            logerror "🚨 the value of $name appears in the staged diff"
            nb_leaks=$((nb_leaks+1))
        fi
    else
        set +e
        hits=$(git grep -l -F -- "$value" 2>/dev/null)
        untracked_hits=$(git ls-files --others --exclude-standard -z 2>/dev/null | xargs -0 grep -l -F -- "$value" 2>/dev/null)
        set -e
        all_hits=$(printf '%s\n%s\n' "$hits" "$untracked_hits" | awk 'NF' | sort -u)
        if [ -n "$all_hits" ]
        then
            logerror "🚨 the value of $name appears in:"
            echo "$all_hits" | sed 's/^/     /'
            nb_leaks=$((nb_leaks+1))
        fi
    fi
done

echo ""
if [ $nb_leaks -gt 0 ]
then
    logerror "🚨 $nb_leaks secret(s) found in clear text — do not commit"
    exit 1
fi

log "✅ No stored secret value found"
