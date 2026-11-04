file="${args[--file]}"
key="${args[--key]}"
truststore="${args[--truststore]}"
password="${args[--password]}"
truststore_password="${args[--truststore-password]}"
server="${args[--server]}"
servername="${args[--servername]}"
hostname="${args[--hostname]}"
purpose="${args[--purpose]}"
json="${args[--json]}"
output_dir="${args[--output-dir]}"
no_open="${args[--no-open]}"
verbose="${args[--verbose]}"

if [[ -z "$file" && -z "$server" ]]
then
    logerror "❌ pass --file (keystore, truststore, PEM or DER certificate) and/or --server <host:port>"
    exit 1
fi
if [[ -n "$server" && "$server" != *:* ]]
then
    logerror "❌ --server must be <host>:<port>, for example broker:9093"
    exit 1
fi
if [[ -n "$key" && -z "$file" && -z "$server" ]]
then
    logerror "❌ --key needs the certificate: --file or --server"
    exit 1
fi

# --server: the hostname of the connection is the host of the server, unless --hostname
if [[ -n "$server" && -z "$hostname" ]]
then
    hostname="${server%:*}"
fi

get_connect_image
set +e

tmp_dir=$(mktemp -d -t pg-cert-inspect-XXXXXXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/in"
cp "$root_folder/scripts/cli/src/ssl/cert-inspect.sh" "$tmp_dir/cert-inspect.sh"
# copies with a prefix: the file, the key and the truststore may have the same name in different folders
env_args=()
if [[ -n "$file" ]]
then
    cp "$file" "$tmp_dir/in/$(basename "$file")"
    env_args+=(-e "FILE=$(basename "$file")")
fi
if [[ -n "$key" ]]
then
    cp "$key" "$tmp_dir/in/key-$(basename "$key")"
    env_args+=(-e "KEY=key-$(basename "$key")")
fi
if [[ -n "$truststore" ]]
then
    cp "$truststore" "$tmp_dir/in/truststore-$(basename "$truststore")"
    env_args+=(-e "TRUSTSTORE=truststore-$(basename "$truststore")")
fi
env_args+=(-e "PASSWORD=$password" -e "TRUSTSTORE_PASSWORD=$truststore_password" -e "SERVER=$server" -e "SERVERNAME=$servername")

# --server on a container of the playground: run in its network, so that its name resolves
network_args=()
if [[ -n "$server" ]]
then
    network=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "${server%:*}" 2> /dev/null | awk '{print $1}')
    if [[ -n "$network" ]]
    then
        network_args=(--network "$network")
    fi
fi

docker_cmd=(docker run --rm -u0 "${network_args[@]}" -v "$tmp_dir:/work" "${env_args[@]}" "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" bash /work/cert-inspect.sh)
if [[ -n "$verbose" ]]
then
    log_verbose_command "$(printf '%s ' "${docker_cmd[@]}" | sed -E 's/(PASSWORD=)[^ ]+/\1*****/g')"
fi
records=$("${docker_cmd[@]}" 2> "$tmp_dir/docker.err")
if [[ -z "$records" ]]
then
    logerror "❌ the inspection did not run in ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}:"
    tail -5 "$tmp_dir/docker.err" >&2
    exit 1
fi

# the inner script writes "-" for an empty field (read collapses consecutive tabs): dash_empty turns it back
function dash_empty () {
    [[ "$1" == "-" ]] && echo "" || echo "$1"
}

now=$(date +%s)
function day () {
    jq -rn --argjson e "$1" '$e | strftime("%Y-%m-%d")'
}

# hostname verification like java: a SAN DNS entry (a wildcard covers one label) or a SAN IP; the CN is not used
function host_matches () {
    local host san value
    host=$(tr '[:upper:]' '[:lower:]' <<< "$1")
    for san in ${2//,/ }
    do
        value=$(tr '[:upper:]' '[:lower:]' <<< "${san#*:}")
        case "$san" in
            DNS:*)
                if [[ "$value" == "$host" ]]
                then
                    return 0
                fi
                if [[ "$value" == \*.* && "$host" == *.* && "${host#*.}" == "${value#\*.}" ]]
                then
                    return 0
                fi
            ;;
            IP:*)
                [[ "$value" == "$host" ]] && return 0
            ;;
        esac
    done
    return 1
}

# checks: one per line "<entry>\t<status>\t<check>\t<value>\t<fix>"
checks_file="$tmp_dir/checks"
: > "$checks_file"
function check () {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" >> "$checks_file"
}

entries=$(awk -F'\t' '$1 == "ENTRY" { print $2 "\t" $3 }' <<< "$records")
while IFS=$'\t' read -r entry kind
do
    [[ -z "$entry" ]] && continue
    certs=$(awk -F'\t' -v e="$entry" '$1 == "CERT" && $2 == e' <<< "$records")
    nb=$(grep -c . <<< "$certs")
    # expiry of every certificate
    while IFS=$'\t' read -r _ _ index subject issuer serial not_before not_after sans key_alg key_bits sig_alg ku eku ca self fp
    do
        sans=$(dash_empty "$sans"); ku=$(dash_empty "$ku"); eku=$(dash_empty "$eku")
        days=$(( (not_after - now) / 86400 ))
        cn=$(sed -E 's/^.*CN=([^,]*).*$/\1/' <<< "$subject")
        if [ "$not_after" -lt "$now" ]
        then
            check "$entry" fail "expiry of #$index ($cn)" "expired on $(day "$not_after")" "renew the certificate ('playground tools cert create' for the playground ones)"
        elif [ "$not_before" -gt "$now" ]
        then
            check "$entry" fail "validity of #$index ($cn)" "not valid before $(day "$not_before")" "check the clock of the machine that created it"
        elif [ "$days" -lt 30 ]
        then
            check "$entry" warn "expiry of #$index ($cn)" "expires in $days day(s), on $(day "$not_after")" "renew it before"
        fi
        if [[ "$key_alg" == rsaEncryption && "$key_bits" =~ ^[0-9]+$ && "$key_bits" -lt 2048 ]]
        then
            check "$entry" warn "key size of #$index ($cn)" "RSA $key_bits bits" "java 8u291+ and recent JDKs refuse RSA keys under 2048 bits by default (jdk.certpath.disabledAlgorithms)"
        fi
        if [[ "$sig_alg" == *sha1* || "$sig_alg" == *SHA1* ]] && [[ "$self" != "yes" ]]
        then
            check "$entry" warn "signature of #$index ($cn)" "$sig_alg" "SHA-1 signatures are disabled in recent JDKs: re-sign with SHA-256"
        fi
    done <<< "$certs"

    if [[ "$kind" == "trustedCertEntry" ]]
    then
        continue
    fi

    # the chain: each certificate issued by the next one, ending at a root (self signed) or not
    order_ok=1
    prev_issuer=""
    while IFS=$'\t' read -r _ _ index subject issuer _
    do
        if [[ -n "$prev_issuer" && "$prev_issuer" != "$subject" ]]
        then
            order_ok=0
        fi
        prev_issuer="$issuer"
    done <<< "$certs"
    last=$(tail -1 <<< "$certs")
    last_self=$(cut -f16 <<< "$last")
    last_issuer=$(cut -f5 <<< "$last")
    if [ "$nb" -gt 1 ]
    then
        if [ $order_ok -eq 1 ]
        then
            check "$entry" ok "chain order" "$nb certificates, each one issued by the next one"
        else
            check "$entry" fail "chain order" "a certificate is not issued by the next one: out of order, or an intermediate is missing" "rebuild the chain in order: leaf, intermediate(s), root (keytool -importcert of the CA reply with the whole chain)"
        fi
    fi
    if [[ "$last_self" == "yes" ]]
    then
        [ "$nb" -gt 1 ] && check "$entry" ok "chain end" "ends with the root ($(sed -E 's/^.*CN=([^,]*).*$/\1/' <<< "$last_issuer"))"
    elif [[ ( "$kind" != "pem" && "$kind" != "der" ) || "$nb" -gt 1 ]]
    then
        check "$entry" info "chain end" "ends at a certificate issued by $last_issuer, not included: the truststore of the peers must contain it"
    fi

    leaf=$(head -1 <<< "$certs")
    leaf_subject=$(cut -f4 <<< "$leaf")
    leaf_sans=$(dash_empty "$(cut -f9 <<< "$leaf")")
    leaf_eku=$(dash_empty "$(cut -f14 <<< "$leaf")")
    leaf_ca=$(cut -f15 <<< "$leaf")
    if [[ "$leaf_ca" == "true" && "$nb" -gt 1 ]]
    then
        check "$entry" warn "first certificate" "is a CA (basicConstraints CA:TRUE)" "the first certificate of a keystore should be the certificate of the server or client itself"
    fi
    if [[ -n "$hostname" ]]
    then
        if [[ -z "$leaf_sans" ]]
        then
            check "$entry" fail "hostname $hostname" "no subject alternative name (the CN is not used)" "java fails with 'No subject alternative names present': regenerate with -ext SAN=dns:$hostname"
        elif host_matches "$hostname" "$leaf_sans"
        then
            check "$entry" ok "hostname $hostname" "in the SANs ($leaf_sans)"
        else
            check "$entry" fail "hostname $hostname" "not in the SANs ($leaf_sans)" "java fails with 'No subject alternative names matching ... found': regenerate with -ext SAN=dns:$hostname, or set ssl.endpoint.identification.algorithm= (empty) on the client to skip the check"
        fi
    fi
    if [[ -n "$purpose" && -z "$leaf_eku" ]]
    then
        check "$entry" ok "extended key usage ($purpose)" "none: the certificate may be used by a server and by a client"
    elif [[ -n "$purpose" ]]
    then
        wanted="TLS Web Server Authentication"
        [[ "$purpose" == "client" ]] && wanted="TLS Web Client Authentication"
        if [[ "$leaf_eku" == *"$wanted"* ]]
        then
            check "$entry" ok "extended key usage ($purpose)" "$leaf_eku"
        else
            check "$entry" fail "extended key usage ($purpose)" "$leaf_eku" "the peer refuses it ('extended key usage does not permit use for TLS $purpose authentication'): add ${purpose}Auth to the extendedKeyUsage of the certificate"
        fi
    fi
done <<< "$entries"

while IFS=$'\t' read -r _ entry result detail
do
    [[ -z "$entry" ]] && continue
    case "$result" in
        match) check "$entry" ok "private key" "$detail" ;;
        mismatch) check "$entry" fail "private key" "$detail" "use the key the certificate was created from (a keystore built from another CSR: 'Public keys in reply and keystore don't match')" ;;
        *) check "$entry" warn "private key" "$detail" ;;
    esac
done < <(awk -F'\t' '$1 == "KEY"' <<< "$records")

while IFS=$'\t' read -r _ entry result detail
do
    [[ -z "$entry" ]] && continue
    if [[ "$result" == "ok" ]]
    then
        check "$entry" ok "truststore $(basename "$truststore")" "trusts the chain"
    else
        # the openssl verify error, in the words of the chain
        case "$detail" in
            *"self-signed certificate in certificate chain"*|*"self signed certificate in certificate chain"*)
                detail="none of the certificates of the chain is in the truststore (it ends with a root the truststore does not have)" ;;
            *"unable to get local issuer certificate"*|*"unable to get issuer certificate"*)
                detail="the truststore does not have the CA that issued the last certificate of the chain ($(awk -F'\t' -v e="$entry" '$1 == "CERT" && $2 == e { i = $5 } END { print i }' <<< "$records"))" ;;
            *"certificate has expired"*)
                detail="a certificate of the chain has expired" ;;
        esac
        check "$entry" fail "truststore $(basename "$truststore")" "does not trust the chain: $detail" "java fails with 'PKIX path building failed: unable to find valid certification path to requested target': import the root (or the intermediate) CA of the chain into the truststore"
    fi
done < <(awk -F'\t' '$1 == "VERIFY"' <<< "$records")

errors=$(awk -F'\t' '$1 == "ERROR" { print $2 }' <<< "$records")
nb_fail=$(awk -F'\t' '$2 == "fail"' "$checks_file" | grep -c .)
nb_warn=$(awk -F'\t' '$2 == "warn"' "$checks_file" | grep -c .)
nb_ok=$(awk -F'\t' '$2 == "ok"' "$checks_file" | grep -c .)
[[ -n "$errors" ]] && nb_fail=$((nb_fail + $(grep -c . <<< "$errors")))

json_result=$(jq -n --rawfile records <(printf '%s\n' "$records") --rawfile checks "$checks_file" --argjson fail "$nb_fail" --argjson warn "$nb_warn" --argjson ok "$nb_ok" '
        ($records | split("\n") | map(select(length > 0) | split("\t") | map(if . == "-" then "" else . end))) as $r
        | ($checks | split("\n") | map(select(length > 0) | split("\t"))) as $c
        | {
            verdict: (if $fail > 0 then "fail" elif $warn > 0 then "warn" else "ok" end), ok: $ok, fail: $fail, warn: $warn,
            errors: [$r[] | select(.[0] == "ERROR") | .[1]],
            info: [$r[] | select(.[0] == "INFO") | .[1]],
            entries: [$r[] | select(.[0] == "ENTRY") | . as $e | {
                entry: $e[1], kind: $e[2],
                tls: ([$r[] | select(.[0] == "TLS" and .[1] == $e[1]) | {protocol: .[2], cipher: .[3]}] | first),
                certificates: [$r[] | select(.[0] == "CERT" and .[1] == $e[1]) | {index: (.[2] | tonumber), subject: .[3], issuer: .[4], serial: .[5],
                    not_before: (.[6] | tonumber | todate), not_after: (.[7] | tonumber | todate), sans: (.[8] | if . == "" then [] else split(",") end),
                    key: "\(.[9]) \(.[10])", signature: .[11], key_usage: .[12], extended_key_usage: .[13], ca: (.[14] == "true"), self_signed: (.[15] == "yes"), sha256: .[16]}],
                checks: [$c[] | select(.[0] == $e[1]) | {status: .[1], check: .[2], value: .[3]} + (if (.[4] // "") == "" then {} else {fix: .[4]} end)]
            }]
        }')

if [[ -n "$json" ]]
then
    printf '%s\n' "$json_result"
else
    while IFS=$'\t' read -r _ message
    do
        [[ -n "$message" ]] && log "$message"
    done < <(awk -F'\t' '$1 == "INFO"' <<< "$records")
    while IFS= read -r message
    do
        [[ -n "$message" ]] && logerror "❌ $message"
    done <<< "$errors"
    while IFS=$'\t' read -r entry kind
    do
        [[ -z "$entry" ]] && continue
        tls=$(awk -F'\t' -v e="$entry" '$1 == "TLS" && $2 == e { print $3 ", " $4 }' <<< "$records")
        log "🔐 $entry ($kind${tls:+, $tls})"
        while IFS=$'\t' read -r _ _ index subject issuer serial not_before not_after sans key_alg key_bits sig_alg ku eku ca self fp
        do
            [[ -z "$index" ]] && continue
            sans=$(dash_empty "$sans"); ku=$(dash_empty "$ku"); eku=$(dash_empty "$eku")
            days=$(( (not_after - now) / 86400 ))
            printf '   #%s %s%s\n' "$index" "$subject" "$( [[ "$self" == "yes" ]] && echo "  (self signed)" )"
            [[ "$self" != "yes" ]] && printf '      issuer   %s\n' "$issuer"
            printf '      valid    %s → %s (%s)\n' "$(day "$not_before")" "$(day "$not_after")" "$( [ "$days" -ge 0 ] && echo "$days days left" || echo "expired $(( -days )) days ago")"
            [[ -n "$sans" ]] && printf '      SAN      %s\n' "$sans"
            printf '      key      %s %s bits, %s%s\n' "${key_alg/rsaEncryption/RSA}" "$key_bits" "$sig_alg" "$( [[ "$ca" == "true" ]] && echo ", CA")"
            [[ -n "$ku$eku" ]] && printf '      usage    %s\n' "$(sed 's/^ | //;s/ | $//' <<< "$ku | $eku")"
            printf '      sha256   %s\n' "$fp"
        done < <(awk -F'\t' -v e="$entry" '$1 == "CERT" && $2 == e' <<< "$records")
        width=0
        while IFS=$'\t' read -r _ _ name _
        do
            [ ${#name} -gt $width ] && width=${#name}
        done < <(awk -F'\t' -v e="$entry" '$1 == e' "$checks_file")
        while IFS=$'\t' read -r _ status name value fix
        do
            case "$status" in
                ok) icon="✅" ;;
                fail) icon="❌" ;;
                warn) icon="⚠️ " ;;
                *) icon="ℹ️ " ;;
            esac
            printf '   %s %-*s  %s\n' "$icon" "$width" "$name" "$value"
            [[ -n "$fix" ]] && printf '      👉 %s\n' "$fix"
        done < <(awk -F'\t' -v e="$entry" '$1 == e' "$checks_file")
    done <<< "$entries"
    # the HTML report: the same result, explained for someone new to TLS
    output_dir="${output_dir:-/tmp/playground-cert-inspect}"
    mkdir -p "$output_dir"
    output_dir=$(cd "$output_dir" && pwd)
    label=$(printf '%s' "${file:+$(basename "$file")}${server:+${file:+-}$server}" | tr -c 'A-Za-z0-9._-' '_')
    report="$output_dir/cert-inspect-${label}-$(date '+%Y%m%d-%H%M%S').html"
    printf '%s\n' "$json_result" > "$tmp_dir/result.json"
    if python3 -I -B "$root_folder/tools/cert-inspect/cert_report.py" --json-file "$tmp_dir/result.json" --out "$report" \
        --file "$file" --server "$server" --hostname "$hostname" --truststore "$truststore" --purpose "$purpose" 2> "$tmp_dir/report.err"
    then
        open_html_report "$report" "$no_open"
    else
        logwarn "⚠️ could not write the HTML report: $(tail -1 "$tmp_dir/report.err")"
    fi
    if [ "$nb_fail" -gt 0 ]
    then
        logerror "❌ $nb_fail problem(s), ⚠️ $nb_warn warning(s), ✅ $nb_ok ok"
    elif [ "$nb_warn" -gt 0 ]
    then
        logwarn "⚠️ $nb_warn warning(s), ✅ $nb_ok ok"
    else
        log "✅ no problem found ($nb_ok check(s) ok)"
    fi
fi

if [ "$nb_fail" -gt 0 ]
then
    exit 1
fi
