file="${args[--file]}"
key="${args[--key]}"
to="${args[--to]}"
password="${args[--password]}"
output_password="${args[--output-password]}"
alias="${args[--alias]}"
output_folder="${args[--output-folder]}"
force="${args[--force]}"
verbose="${args[--verbose]}"

if [[ -n "$key" ]] && grep -q -- "-----BEGIN CERTIFICATE" "$key" 2> /dev/null && ! grep -q -- "PRIVATE KEY-----" "$key"
then
    logerror "❌ --key $key holds no private key (-----BEGIN ... PRIVATE KEY-----)"
    exit 1
fi

output_folder="${output_folder:-$(dirname "$file")}"
mkdir -p "$output_folder"
output_folder=$(cd "$output_folder" && pwd)
base=$(basename "$file")
base="${base%.*}"

get_connect_image
set +e

tmp_dir=$(mktemp -d -t pg-cert-convert-XXXXXXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/in" "$tmp_dir/out"
cp "$root_folder/scripts/cli/src/ssl/cert-convert.sh" "$tmp_dir/cert-convert.sh"
cp "$file" "$tmp_dir/in/$(basename "$file")"
env_args=(-e "FILE=$(basename "$file")" -e "TO=$to" -e "PASSWORD=$password" -e "OUTPUT_PASSWORD=$output_password" -e "ALIAS=$alias" -e "BASE=$base")
if [[ -n "$key" ]]
then
    cp "$key" "$tmp_dir/in/key-$(basename "$key")"
    env_args+=(-e "KEY=key-$(basename "$key")")
fi

docker_cmd=(docker run --rm -u0 -v "$tmp_dir:/work" "${env_args[@]}" "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" bash /work/cert-convert.sh)
if [[ -n "$verbose" ]]
then
    log_verbose_command "$(printf '%s ' "${docker_cmd[@]}" | sed -E 's/(PASSWORD=)[^ ]+/\1*****/g')"
fi
log "🔄 Converting $(basename "$file") to $to"
records=$("${docker_cmd[@]}" 2> "$tmp_dir/docker.err")
if [[ -z "$records" ]]
then
    logerror "❌ the conversion did not run in ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}:"
    tail -5 "$tmp_dir/docker.err" >&2
    exit 1
fi

while IFS=$'\t' read -r _ message
do
    [[ -n "$message" ]] && log "$message"
done < <(awk -F'\t' '$1 == "INFO"' <<< "$records")
errors=$(awk -F'\t' '$1 == "ERROR" { print $2 }' <<< "$records")
while IFS= read -r message
do
    [[ -n "$message" ]] && logerror "❌ $message"
done <<< "$errors"

outputs=$(awk -F'\t' '$1 == "OUT"' <<< "$records")
if [[ -z "$outputs" ]]
then
    exit 1
fi

# the files written in the container, copied to the output folder: an existing file is only replaced with --force
written=()
while IFS=$'\t' read -r _ name what
do
    [[ -z "$name" ]] && continue
    if [[ -e "$output_folder/$name" && -z "$force" ]]
    then
        logerror "❌ $output_folder/$name exists already: not replaced (pass --force, or --output-folder)"
        continue
    fi
    cp "$tmp_dir/out/$name" "$output_folder/$name"
    written+=("$output_folder/$name")
    log "✅ $output_folder/$name"
    printf '   %s\n' "$what"
done <<< "$outputs"

if [ ${#written[@]} -eq 0 ]
then
    exit 1
fi

store_pass_hint="${output_password:-the password of $(basename "$file") (or 'confluent')}"
case "$to" in
    pkcs12|jks)
        log "🎓 use it with ssl.keystore.location (or ssl.truststore.location), ssl.*.type=$( [[ "$to" == "jks" ]] && echo JKS || echo PKCS12) and the password: $store_pass_hint"
    ;;
    pem)
        log "🎓 librdkafka clients (python, go, .net, C): ssl.ca.location, ssl.certificate.location, ssl.key.location$( [[ -n "$output_password" ]] && echo ", ssl.key.password")"
    ;;
    properties)
        log "🎓 add these lines to the client properties (security.protocol=SSL or SASL_SSL): the certificates are inline, no file to copy"
    ;;
esac
first_inspectable=""
for f in "${written[@]}"
do
    case "$f" in
        *.properties|*.key.pem) ;;
        *) first_inspectable="$f"; break ;;
    esac
done
if [[ -n "$first_inspectable" ]]
then
    log "🔍 check the result: playground tools cert inspect --file $first_inspectable$( [[ "$to" == "pkcs12" || "$to" == "jks" ]] && [[ -n "$output_password" ]] && echo " --password <output password>")"
fi
if [[ -n "$errors" ]]
then
    exit 1
fi
