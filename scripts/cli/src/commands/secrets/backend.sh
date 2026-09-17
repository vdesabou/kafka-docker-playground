backend="${args[backend]}"

if [[ ! -n "$backend" ]]
then
    log "🔐 Current secrets backend: $(get_secret_backend)"
    log "🎓 Tip: playground secrets backend <keychain|secret-tool|pass|op|vault|file>"
    exit 0
fi

case "$backend" in
    keychain)
        if [[ "$OSTYPE" != "darwin"* ]]
        then
            logerror "❌ the keychain backend is only available on macOS"
            exit 1
        fi
    ;;
    secret-tool|pass|op|vault)
        if ! command -v "$backend" > /dev/null 2>&1
        then
            logerror "❌ $backend is not installed"
            exit 1
        fi
    ;;
    file)
        logwarn "⚠️ the file backend keeps values in $(get_secrets_file) (mode 0600) without encryption"
        logwarn "👉 prefer keychain, pass, op or vault when one of them is available"
    ;;
esac

playground config set secrets.backend "$backend"
log "🔐 Secrets backend set to $backend"

case "$backend" in
    op)
        vault=$(get_op_vault)
        log "🏦 1Password items will be created in vault $vault"
        log "🎓 change it with: playground config set secrets.op-vault <vault>"
        log "🎓 you can also point a variable at an item you already have:"
        log "   playground secrets link SALESFORCE_PASSWORD op://Private/salesforce/password"

        if ! op whoami > /dev/null 2>&1
        then
            logwarn "⚠️ not signed in to 1Password"
            logwarn "👉 enable 'Integrate with 1Password CLI' in the desktop app, or run: eval \$(op signin)"
        elif ! op vault get "$vault" > /dev/null 2>&1
        then
            logwarn "⚠️ vault $vault is not readable with your current 1Password session"
            logwarn "👉 playground config set secrets.op-vault <one of: $(op vault list --format json 2>/dev/null | jq -r '[.[].name] | join(", ")' 2>/dev/null)>"
        fi
    ;;
    vault)
        log "🎓 vault is reference-only: store the secret in Vault, then run"
        log "   playground secrets link SALESFORCE_PASSWORD vault://secret/kdp/salesforce#password"
    ;;
esac
