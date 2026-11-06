profile="${args[--profile]:-$(get_active_secret_profile)}"
dry_run="${args[--dry-run]}"

codespace=$(codespace_pick "${args[--codespace]}") || exit 1

names=$(secret_store_names "$profile")
if [ -z "$names" ]
then
    logerror "❌ profile $profile is empty, there is nothing to send"
    logerror "👉 playground secrets import --file <secret.properties>"
    exit 1
fi

secret_backend_ready || exit 1

#
# Two payloads, so that the codespace files each variable where the laptop does
# (secrets.ini or env.ini), whatever its name: 'secrets import --secret' and
# '--plain' instead of guessing again from the name.
#
secret_build_payload "$profile" secret import
payload_secret="$SECRET_PAYLOAD"
nb_secret=$SECRET_PAYLOAD_NB
nb_failed=$SECRET_PAYLOAD_NB_FAILED
secret_build_payload "$profile" plain import
payload_plain="$SECRET_PAYLOAD"
nb_plain=$SECRET_PAYLOAD_NB
nb_failed=$((nb_failed+SECRET_PAYLOAD_NB_FAILED))
nb=$((nb_secret+nb_plain))

if [ $nb -eq 0 ]
then
    logerror "❌ no value of profile $profile could be resolved, nothing to send"
    exit 1
fi

# the credentials that are files, not name=value pairs (see SECRET_PUSH_FILES)
secret_push_available_files
available_files=("${SECRET_PUSH_AVAILABLE_FILES[@]}")

if [[ -n "$dry_run" ]]
then
    log "🔍 $nb variable(s) of profile $profile would be imported into the secrets store of codespace $codespace ($nb_secret credential(s), $nb_plain plain variable(s))"
    for entry in "${available_files[@]}"
    do
        rest="${entry#*:}"
        log "🔍 $root_folder/${entry%%:*} would be sent to ~/${rest%%:*} (mode ${rest##*:})"
    done
    exit 0
fi

codespace_wait_ssh "$codespace" || exit 1

remote_playground="$(codespace_remote_root)/scripts/cli/playground"

#
# The payload lands in a temporary file (umask 077: never readable by anyone
# else), is imported with the file backend (there is no keychain in a
# codespace), then shredded. The import prints one line per variable: only its
# summary is shown, unless it fails.
#
function import_into_codespace () {
    local kind="$1" payload="$2" nb_kind="$3" remote_command output
    [ "$nb_kind" -gt 0 ] || return 0
    printf -v remote_command 'umask 077 && tmp=$(mktemp) && cat > "$tmp" && PLAYGROUND_SECRETS_BACKEND=file bash %q secrets import --file "$tmp" --%s --profile %q --shred 2>&1; rc=$?; rm -f "$tmp"; exit $rc' \
        "$remote_playground" "$kind" "$profile"
    if output=$(printf '%s' "$payload" | gh codespace ssh -c "$codespace" -- "$remote_command")
    then
        # the summary line of 'secrets import': ✅ Imported <n> secret(s) and <m> plain variable(s), <k> skipped
        log "$(echo "$output" | sed -e 's/\x1b\[[0-9;]*m//g' | grep "Imported" | tail -1 | sed -e 's/^.*✅/✅/') (codespace $codespace)"
    else
        echo "$output"
        logerror "❌ could not import the $kind variables into codespace $codespace"
        exit 1
    fi
}

log "🔐 Sending $nb variable(s) of profile $profile to codespace $codespace ($nb_secret credential(s), $nb_plain plain variable(s))"
import_into_codespace secret "$payload_secret" "$nb_secret"
import_into_codespace plain "$payload_plain" "$nb_plain"

for entry in "${available_files[@]}"
do
    local_file="$root_folder/${entry%%:*}"
    rest="${entry#*:}"
    remote_path="${rest%%:*}"
    mode="${rest##*:}"

    log "🔐 Sending $(basename "$local_file") to codespace $codespace (~/$remote_path)"
    remote_script=$(secret_push_file_remote_script "$remote_path" "$mode")
    if gh codespace ssh -c "$codespace" -- "$remote_script" < "$local_file"
    then
        log "✅ ~/$remote_path written in codespace $codespace"
    else
        logerror "❌ could not write ~/$remote_path in codespace $codespace"
        exit 1
    fi
done

log "🎓 'playground run' in the codespace now loads what each example needs from its secrets store ('playground secrets list' there)"
if [ "$profile" != "default" ]
then
    log "👉 profile $profile is not the active one in the codespace: playground codespace ssh --codespace $codespace -- playground secrets profile $profile"
fi
log "⚠️ 'Codespaces: Rebuild Container' empties the home directory: run 'playground codespace push-secrets' again after a rebuild"

if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed variable(s) could not be resolved and were left out"
fi
