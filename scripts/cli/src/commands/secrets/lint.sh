cd "$root_folder"

#
# An example declares the variables it needs with the standard error string:
#
#   logerror "FOO is not set. Export it as environment variable or pass it as argument"
#
# Only those are auto-detected by `playground run` and `playground secrets check`.
# This reports the ones checked with a bare `if [ -z "$FOO" ]` instead.
#
search_dirs="connect ccloud ksqldb flink schema-registry rest-proxy multi-data-center other operator academy environment"

# set by the CLI, by an example flag or by CI, never by the user
ignored="GITHUB_RUN_NUMBER CONNECTOR_TAG CONNECTOR_ZIP CONNECTOR_JAR CONNECT_TAG LATEST_TAG CLASSPATH CLOUDFORMATION KAFKA_CLUSTER_ID"

log "🔎 Looking for environment variables checked without the standard marker"

# one pass for the bare checks, keeping the file each one is in
bare_checks=$(grep -rnE 'if \[ -z "\$[A-Z][A-Z0-9_]*"' --include="*.sh" $search_dirs 2>/dev/null \
  | sed -E 's|^([^:]+):[0-9]+:.*\$([A-Z][A-Z0-9_]*).*|\2 \1|' \
  | sort -u)

# one pass for the properly declared ones
declared=$(grep -rhoE '"[A-Z][A-Z0-9_]* is not set\. Export it as environment variable' --include="*.sh" $search_dirs 2>/dev/null \
  | grep -oE '"[A-Z][A-Z0-9_]*' | tr -d '"' | sort -u)

nb=0
for name in $(echo "$bare_checks" | awk '{print $1}' | sort -u)
do
    case " $ignored " in
        *" $name "*) continue ;;
    esac
    case " $(echo $declared) " in
        *" $name "*) continue ;;
    esac
    # ENABLE_* are playground flags, not credentials
    case "$name" in
        ENABLE_*) continue ;;
    esac

    nb=$((nb+1))
    files=$(echo "$bare_checks" | awk -v n="$name" '$1==n {print $2}' | head -3 | tr '\n' ' ')
    if is_secret_env_var_name "$name"
    then
        printf "🔐 %-42s %s\n" "$name" "$files"
    else
        printf "📝 %-42s %s\n" "$name" "$files"
    fi
done

echo ""
if [ $nb -eq 0 ]
then
    log "✅ Every environment variable uses the standard marker"
    exit 0
fi

logwarn "⚠️ $nb variable(s) are not auto-detected by 'playground run' and 'playground secrets check'"
logwarn "👉 in the example, replace the bare check with:"
logwarn '   logerror "FOO is not set. Export it as environment variable or pass it as argument"'
