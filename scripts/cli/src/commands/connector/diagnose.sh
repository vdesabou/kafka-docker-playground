connector="${args[--connector]}"
verbose="${args[--verbose]}"
since="${args[--since]}"
max_findings="${args[--max-findings]}"
output_dir="${args[--output-dir]:-/tmp/playground-diagnose}"
no_open="${args[--no-open]}"
json="${args[--json]}"
fail_on_error="${args[--fail-on-error]}"

# --json: the steps write to stderr, only the JSON array goes to stdout (fd 3); the HTML report is written, not opened
if [[ -n "$json" ]]
then
    exec 3>&1 1>&2
    no_open=1
fi
unhealthy=0

connector_type=$(playground state get run.connector_type)
get_environment_used
# get_ccloud_connect overwrites $environment with the Confluent Cloud environment id
playground_environment="$environment"

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi

maybe_verbose=""
if [[ -n "$verbose" ]]
then
    maybe_verbose="--verbose"
fi

is_cloud=0
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    is_cloud=1
fi

diagnose_connect_container="connect"
if is_mdc_environment
then
    get_connect_container
    diagnose_connect_container="$connect_container"
fi

# each step also lands in a folder per connector, for the HTML report (tools/connector-diagnose/diagnose_report.py)
report_tmp=$(mktemp -d -t pg-diagnose-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $report_tmp' EXIT
else
    log "🐛📂 not deleting tmp dir $report_tmp"
fi
connector_dirs=()

for connector in "${items[@]}"
do
    cdir="$report_tmp/${#connector_dirs[@]}"
    mkdir -p "$cdir"
    connector_dirs+=("$cdir")

    log "####################################################"
    log "🩺 diagnosing $connector_type connector $connector"
    log "####################################################"

    echo ""
    log "🗺️  1/4 status"
    PG_SKIP_DIAGNOSE_HINT=1 playground connector status --connector "$connector" $maybe_verbose

    # sink or source, and state, from the status endpoint
    if [ $is_cloud -eq 1 ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
    fi
    type=$(echo "$curl_output" | jq -r '.type // empty')
    connector_state=$(echo "$curl_output" | jq -r '.connector.state // empty')
    task_states=$(echo "$curl_output" | jq -r '[.tasks[]?.state] | unique | join(",")')
    if [ -z "$connector_state" ] || [[ "$connector_state" == "FAILED" ]] || [[ "$task_states" == *"FAILED"* ]]
    then
        unhealthy=$((unhealthy + 1))
    fi
    echo "$curl_output" > "$cdir/status.json"
    jq -n --arg connector "$connector" --arg connector_type "$connector_type" --arg is_cloud "$is_cloud" --arg type "$type" \
        --arg since "$since" --arg environment "$playground_environment" \
        '{connector: $connector, connector_type: $connector_type, is_cloud: $is_cloud, type: $type, since: $since, environment: $environment}' > "$cdir/meta.json"
    if [ $is_cloud -eq 1 ]
    then
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1 && echo "$curl_output" > "$cdir/config.json"
    else
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/config\"" > /dev/null 2>&1 && echo "$curl_output" > "$cdir/config.json"
    fi

    echo ""
    if [ $is_cloud -eq 1 ]
    then
        log "🔥 2/4 errors: Confluent Cloud error recommendations"
        playground connector error-recommendations --connector "$connector" $maybe_verbose | tee "$cdir/recommendations.txt"
        display_ccloud_connector_service_account_acl_check "$connector"
    else
        log "🔥 2/4 errors: digest of connect ERROR/FATAL records since $since (whole worker, not only this connector)"
        PG_LOG_DIGEST_RECORDS_FILE="$cdir/errors.records" PG_LOG_DIGEST_LABEL="$diagnose_connect_container" playground container logs --container "$diagnose_connect_container" --errors --since "$since" --max-findings "$max_findings"
    fi

    echo ""
    if [ "$type" == "sink" ]
    then
        if [[ "$connector_state" == "RUNNING" ]] && [[ "$task_states" == "RUNNING" ]]
        then
            log "🐢 3/4 progress: consumer lag of sink $connector"
            { playground connector show-lag --connector "$connector" --interval 1 --max-wait 1 $maybe_verbose || true; } | tee "$cdir/lag.txt"
        else
            # show-lag waits 60s for a RUNNING task and then fails, which would hide the next steps
            log "🐢 3/4 progress: committed offsets of sink $connector (no lag while the connector and all its tasks are not RUNNING)"
            { playground connector offsets get --connector "$connector" $maybe_verbose || true; } | tee "$cdir/offsets.txt"
        fi
    elif [ "$type" == "source" ]
    then
        log "🐢 3/4 progress: offsets of source $connector (run it again to see whether they move)"
        { playground connector offsets get --connector "$connector" $maybe_verbose || true; } | tee "$cdir/offsets.txt"
    else
        logwarn "🐢 3/4 progress: unknown connector type <$type>, skipped"
    fi

    echo ""
    log "👉 4/4 next steps"
    # " --cluster us|europe" in mdc environments, otherwise the printed commands target the wrong cluster
    cluster_flag=""
    if [ $is_cloud -eq 0 ]
    then
        cluster_flag=$(mdc_cluster_flag)
    fi
    next_steps=()
    if [[ "$connector_state" == "FAILED" ]] || [[ "$task_states" == *"FAILED"* ]]
    then
        next_steps+=("🔥 a task or the connector FAILED: read the trace above, then after a fix: playground connector restart --connector $connector$cluster_flag")
        # SASL refused: which credentials the clients of the connector use, its own (*.override.sasl.jaas.config, or
        # the admin client of a sink with a DLQ) or the ones of the worker
        if [ $is_cloud -eq 0 ] && grep -q "SaslAuthenticationException" "$cdir/status.json" 2>/dev/null
        then
            override_key=$(jq -r 'to_entries[] | select(.key | test("^(consumer|producer|admin)\\.override\\.sasl\\.jaas\\.config$")) | .key' "$cdir/config.json" 2>/dev/null | head -1)
            if [[ -n "$override_key" ]]
            then
                # (the saved config masks the value: show-config prints it)
                next_steps+=("🔑 SASL authentication refused with the connector's own credentials: $override_key overrides the credentials of the worker. Check its user and password (a rotated password?): playground connector show-config --connector $connector$cluster_flag")
            else
                next_steps+=("🔑 SASL authentication refused with the credentials of the worker (CONNECT_CONSUMER_SASL_JAAS_CONFIG / CONNECT_PRODUCER_SASL_JAAS_CONFIG): playground container get-properties -c $diagnose_connect_container")
            fi
        fi
        # Kerberos: the login of a client (keytab or ticket cache) refused by the KDC, the most common messages explained
        if [ $is_cloud -eq 0 ] && grep -q -E "LoginException: (Checksum failed|Pre-authentication information was invalid|Message stream modified|Clock skew too great|Client not found in Kerberos database|Unable to obtain password)" "$cdir/status.json" 2>/dev/null
        then
            krb_reason=$(grep -o -E "LoginException: (Checksum failed|Pre-authentication information was invalid \(24\)|Message stream modified \(41\)|Clock skew too great \(37\)|Client not found in Kerberos database \(6\)|Unable to obtain password from user)" "$cdir/status.json" 2>/dev/null | head -1 | sed 's/^LoginException: //')
            case "$krb_reason" in
                "Checksum failed"|"Pre-authentication information was invalid"*)
                    krb_what="the key in the keytab is not the current key of the principal on the KDC (keys rotated, password reset): export a new keytab (kadmin ktadd, ktpass on Active Directory) and restart; compare the kvno of klist -kt <keytab> with the one of the KDC" ;;
                "Message stream modified"*)
                    krb_what="krb5.conf asks for renewable tickets (renew_lifetime) and the principal is not renewable: modprinc +allow_renewable -maxrenewlife on the KDC, or remove renew_lifetime" ;;
                "Clock skew too great"*)
                    krb_what="the clock of the worker and of the KDC are more than 5 minutes apart (clockskew of krb5.conf): fix the time synchronization" ;;
                "Client not found in Kerberos database"*)
                    krb_what="the principal does not exist on the KDC: check its name and realm (principal= of the JAAS config, the realm of krb5.conf)" ;;
                *)
                    krb_what="the keytab cannot be read, or has no key for the principal: check keyTab= and principal= of the JAAS config, and the permissions of the file" ;;
            esac
            krb_key=$(jq -r 'to_entries[] | select(.key | test("^(consumer|producer|admin)\\.override\\.sasl\\.jaas\\.config$")) | .key' "$cdir/config.json" 2>/dev/null | head -1)
            next_steps+=("🎫 Kerberos login refused ($krb_reason) with ${krb_key:-the JAAS config of the worker}: $krb_what")
        fi
        # OAuth: the token endpoint refused the client credentials (client_credentials grant): its error, and whose
        # OAuth client it is, the connector's own (*.override.sasl.jaas.config) or the worker's
        if [ $is_cloud -eq 0 ] && grep -q "was encountered reading the token endpoint response" "$cdir/status.json" 2>/dev/null
        then
            oauth_error=$(grep -o -E 'error response \{[^}]{0,200}\}' "$cdir/status.json" 2>/dev/null | head -1 | sed -E 's/^error response //; s/\\"/"/g')
            oauth_key=$(jq -r 'to_entries[] | select(.key | test("^(consumer|producer|admin)\\.override\\.sasl\\.jaas\\.config$")) | .key' "$cdir/config.json" 2>/dev/null | head -1)
            if [[ -n "$oauth_key" ]]
            then
                next_steps+=("🎟️ the token endpoint refused the OAuth client of the connector${oauth_error:+ ($oauth_error)}: $oauth_key (clientId, clientSecret) overrides the client of the worker. Check them against the identity provider (a rotated secret?): playground connector show-config --connector $connector$cluster_flag")
            else
                next_steps+=("🎟️ the token endpoint refused the OAuth client of the worker${oauth_error:+ ($oauth_error)}: its sasl.jaas.config (clientId, clientSecret) and sasl.oauthbearer.token.endpoint.url: playground container get-properties -c $diagnose_connect_container")
            fi
        fi
        # not authorized: the principal and the resource, and on RBAC the role bindings to look at and to create
        if [ $is_cloud -eq 0 ] && grep -q -E "(Topic|Group|TransactionalId|Cluster)AuthorizationException" "$cdir/status.json" 2>/dev/null
        then
            authz_resource=""
            authz_topic=$(grep -o -E "Not authorized to access topics: \[[^]]+\]" "$cdir/status.json" 2>/dev/null | head -1 | sed -E 's/.*\[([^],]+).*/\1/')
            authz_group=$(grep -o -E "Not authorized to access group: [^ \"\\]+" "$cdir/status.json" 2>/dev/null | head -1 | awk '{print $NF}')
            [[ -n "$authz_topic" ]] && authz_resource="Topic:$authz_topic"
            [[ -n "$authz_group" ]] && authz_resource="Group:$authz_group"
            authz_principal=$(jq -r '."principal.service.name" // empty' "$cdir/config.json" 2>/dev/null)
            # the connect rest api of an RBAC worker masks principal.service.* ("••••"): show-config prints it
            # (taken from the example that was run when it is a literal there, as playground connector show-config does)
            authz_masked=""
            if [[ "$authz_principal" == *"•"* ]] || [ "$authz_principal" == "[hidden]" ] || [[ "$authz_principal" =~ ^\*+$ ]]
            then
                authz_test_file=$(playground state get run.test_file 2>/dev/null)
                authz_principal=""
                [ -f "$authz_test_file" ] && authz_principal=$(grep -o -E '"principal\.service\.name"[[:space:]]*:[[:space:]]*"[^"$]*"' "$authz_test_file" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
                [[ -z "$authz_principal" ]] && authz_principal="<principal>" && authz_masked=" (<principal>: principal.service.name, playground connector show-config --connector $connector shows it)"
            fi
            if [[ "$playground_environment" == rbac* || "$playground_environment" == cfk-rbac ]] && [[ -n "$authz_principal" ]]
            then
                authz_role="DeveloperRead"
                [[ "$type" == "source" ]] && authz_role="DeveloperWrite"
                next_steps+=("🚫 User:$authz_principal (principal.service.name) is not authorized${authz_resource:+ on $authz_resource}: playground rbac role-binding list --principal User:$authz_principal, then playground rbac role-binding create --principal User:$authz_principal --role $authz_role --resource ${authz_resource:-<Topic:name>}$( [ "$type" == "sink" ] && [[ "$authz_resource" != Group:* ]] && echo " (a sink also needs DeveloperRead on Group:connect-$connector)")$authz_masked")
            else
                next_steps+=("🚫 the principal of the connector is not authorized${authz_resource:+ on $authz_resource}: its ACLs or role bindings (playground rbac acl list, playground rbac role-binding list)")
            fi
        fi
        # TLS refused: the command that explains the certificate of the broker, with the address the client used
        if [ $is_cloud -eq 0 ] && grep -q -E "SSLHandshakeException|SslAuthenticationException" "$cdir/status.json" 2>/dev/null
        then
            # the most precise reason first (certificate_unknown is the alert that comes with most of them)
            tls_reason=""
            for tls_pattern in "No subject alternative names? (present|matching (IP address|DNS name) [^ \"\\]+)" "PKIX path building failed" "NotAfter: [^\"\\]+" "certificate expired" "certificate_unknown"
            do
                tls_reason=$(grep -o -E "$tls_pattern" "$cdir/status.json" 2>/dev/null | head -1)
                [[ -n "$tls_reason" ]] && break
            done
            tls_host=$(grep -o -E "matching (IP address|DNS name) [^ \"\\]+" "$cdir/status.json" 2>/dev/null | head -1 | awk '{print $NF}')
            tls_server=$(jq -r '."consumer.override.bootstrap.servers" // ."producer.override.bootstrap.servers" // ."admin.override.bootstrap.servers" // empty' "$cdir/config.json" 2>/dev/null | cut -d, -f1)
            next_steps+=("🔐 TLS handshake refused${tls_reason:+ ($tls_reason)}: playground tools cert inspect --server ${tls_server:-<broker host:port>}${tls_host:+ --hostname $tls_host} explains the certificate of the broker and what to change")
        fi
    elif [[ "$connector_state" == "PAUSED" ]] || [[ "$task_states" == *"PAUSED"* ]]
    then
        next_steps+=("⏸️  the connector is PAUSED: playground connector resume --connector $connector$cluster_flag")
    elif [[ "$connector_state" == "RUNNING" ]]
    then
        # a sink task kicked out of its group: it processes longer than max.poll.interval.ms between two polls, so its
        # commit fails and the records are delivered again after the rebalance (the task stays RUNNING, without error)
        if [ "$type" == "sink" ] && [ -s "$cdir/errors.records" ] && grep -q -E "CommitFailedException|consumer poll timeout has expired" "$cdir/errors.records"
        then
            max_poll_interval=$(jq -r '."consumer.override.max.poll.interval.ms" // empty' "$cdir/config.json" 2>/dev/null)
            next_steps+=("🐢 a task was kicked out of its consumer group (CommitFailedException): more than max.poll.interval.ms (${max_poll_interval:-300000 by default}) between two polls, so its offsets are not committed and the records are delivered again. Lower consumer.override.max.poll.records or make each batch faster, or raise consumer.override.max.poll.interval.ms")
        fi
        # a read_committed sink does not read past the first open transaction of a partition: no error, no progress,
        # no offset committed, until the transaction commits, aborts or times out (transaction.timeout.ms)
        if [ "$type" == "sink" ] && [ -s "$cdir/config.json" ] && [ "$(jq -r '."consumer.override.isolation.level" // empty' "$cdir/config.json" 2>/dev/null)" == "read_committed" ]
        then
            first_topic=$(jq -r '.topics // empty' "$cdir/config.json" 2>/dev/null | cut -d, -f1 | tr -d ' ')
            next_steps+=("🔒 the sink reads read_committed: an open transaction blocks it at its first offset, without error. Look for one: playground broker transactions describe-producers --topic ${first_topic:-<topic>}$cluster_flag (OPEN_TRANSACTION_START_OFFSET ⚠️)")
        fi
        next_steps+=("🐌 RUNNING but no progress? run this command again, then take a thread dump if lag or offsets do not move")
    fi
    next_steps+=("playground connector show-config --connector $connector$cluster_flag")
    if [ $is_cloud -eq 1 ]
    then
        next_steps+=("playground connector logs --connector $connector")
    else
        next_steps+=("playground container logs -c $diagnose_connect_container --grep \"$connector\" --no-follow --tail 200")
        next_steps+=("playground connector log-level --connector $connector --level TRACE$cluster_flag")
        next_steps+=("playground debug thread-dump --container $diagnose_connect_container")
    fi
    for step in "${next_steps[@]}"
    do
        echo "   $step"
    done
    printf '%s\n' "${next_steps[@]}" > "$cdir/next_steps.txt"
    echo ""
done

# --fail-on-error: exit 1 when a connector or a task is FAILED, or the connector is not found (after the report)
function diagnose_exit () {
    if [[ -n "$fail_on_error" ]] && [ "$unhealthy" -gt 0 ]
    then
        logerror "❌ $unhealthy connector(s) FAILED, with a FAILED task, or not found"
        exit 1
    fi
    exit 0
}

if ! command -v python3 &>/dev/null
then
    if [[ -n "$json" ]]
    then
        logerror "❌ python3 is not on PATH: --json needs it"
        exit 1
    fi
    logwarn "⚠️ python3 is not on PATH: no HTML report"
    diagnose_exit
fi
report_name="all"
if ((length == 1))
then
    report_name=$(printf '%s' "$connector" | tr -c 'A-Za-z0-9._-' '_')
fi
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
html_out="$output_dir/connector-diagnose-${report_name}-$(date '+%Y%m%d-%H%M%S').html"
report_args=()
for cdir in "${connector_dirs[@]}"
do
    report_args+=(--connector-dir "$cdir")
done
json_args=()
if [[ -n "$json" ]]
then
    json_args=(--json-out "$report_tmp/diagnose.json")
fi
if ! python3 -I "$root_folder/tools/connector-diagnose/diagnose_report.py" "${report_args[@]}" --html-out "$html_out" "${json_args[@]}"
then
    logerror "❌ could not write the HTML report"
    exit 1
fi
open_html_report "$html_out" "$no_open"
if [[ -n "$json" ]]
then
    jq --arg html "$html_out" 'map(. + {html_report: $html})' "$report_tmp/diagnose.json" >&3
fi
diagnose_exit
