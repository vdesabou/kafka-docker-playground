profile="${args[--profile]:-$(get_active_secret_profile)}"
show_source="${args[--show-source]}"

names=$(secret_store_names "$profile")

if [ -z "$names" ]
then
    log "🔐 No secret stored in profile $profile"
    log "👉 playground secrets set <NAME>"
    log "👉 playground secrets import --file <secret.properties>"
    exit 0
fi

log "🔐 Secrets in profile $profile ($(get_secrets_dir))"
echo ""
printf "%-45s %-14s %s\n" "NAME" "BACKEND" "VALUE"
printf "%-45s %-14s %s\n" "----" "-------" "-----"

for name in $names
do
    ref=$(secret_lookup_reference "$name" "$profile" || true)
    backend=$(secret_reference_backend "$ref")

    if [ "$(secret_store_location "$name" "$profile" || true)" == "secret" ]
    then
        value=$(secret_resolve_reference "$ref" || true)
        if [ -z "$value" ]
        then
            display="❌ cannot be resolved"
        else
            display=$(secret_fingerprint "$value")
        fi
    else
        # not sensitive, show it
        display="$ref"
        backend="plain"
    fi

    if [ -n "${!name:-}" ]
    then
        display="$display  ⚠️ overridden by the environment"
    fi

    if [[ -n "$show_source" ]]
    then
        printf "%-45s %-14s %s\n" "$name" "$backend" "$ref"
    else
        printf "%-45s %-14s %s\n" "$name" "$backend" "$display"
    fi
done
echo ""
