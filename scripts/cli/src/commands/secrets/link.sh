name="${args[name]}"
reference="${args[reference]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"

case "$reference" in
    op://*|vault://*|keychain:*|secret-tool:*|pass:*)
    ;;
    *)
        logerror "❌ <$reference> is not a supported reference"
        logerror "👉 expected one of: op://<vault>/<item>/<field>, vault://<path>#<field>, keychain:<profile>:<NAME>, secret-tool:<profile>:<NAME>, pass:<path>"
        exit 1
    ;;
esac

secret_store_set "$(get_secrets_file)" "$profile" "$name" "$reference" "0600"
log "🔗 $name linked to $reference in profile $profile"

value=$(secret_resolve_reference "$reference" || true)
if [ -n "$value" ]
then
    log "✅ reference resolves: $(secret_fingerprint "$value")"
else
    logwarn "⚠️ the reference does not resolve right now (not logged in to $(secret_reference_backend "$reference") ?)"
fi
