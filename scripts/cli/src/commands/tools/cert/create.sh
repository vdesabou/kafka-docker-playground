output_folder="${args[--output-folder]}"
verbose="${args[--verbose]}"
# Convert the space delimited string to an array
eval "containers=(${args[--container]})"

get_connect_image
# get_connect_image ends with set -e: the errors are handled below, with a message
set +e

if ! mkdir -p "${output_folder}" || ! output_folder=$(cd "${output_folder}" && pwd)
then
    logerror "❌ cannot create the output folder ${output_folder}"
    exit 1
fi

new_open_ssl=0
if docker run --rm "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" openssl version | grep -q "OpenSSL 3"
then
    new_open_ssl=1
fi

# only the files of a previous run of the command (the CA, and the files named after each container): the folder can
# hold other files (an example folder, a customer certificate next to a repro model)
rm -f "${output_folder}/snakeoil-ca-1.crt" "${output_folder}/snakeoil-ca-1.key" "${output_folder}/snakeoil-ca-1.srl" "${output_folder}/extfile"
for container in "${containers[@]}"
do
    for f in "kafka.${container}.keystore.jks" "kafka.${container}.truststore.jks" "${container}.csr" "${container}-ca1-signed.crt" \
        "${container}_sslkey_creds" "${container}_keystore_creds" "${container}_truststore_creds" "${container}.der" \
        "${container}.certificate.pem" "${container}.keystore.p12" "${container}.key" "${container}.p12"
    do
        rm -f "${output_folder}/${f}"
    done
done
rm -rf "${output_folder}/hsperfdata_root"

log_file=$(mktemp -t pg-certs-create-XXXXXXXXXX)
function cleanup {
    set +e
    rm -f "${output_folder}/certs-create.sh" "${output_folder}/extfile" "${output_folder}/snakeoil-ca-1.srl" "${log_file}"
    rm -rf "${output_folder}/hsperfdata_root"
}
trap cleanup EXIT

cp "${root_folder}/scripts/cli/src/ssl/certs-create.sh" "${output_folder}/certs-create.sh"
maybe_create_image
set +e
log "🔐 Generate keys and certificates in folder ${output_folder}"
# -XX:-UsePerfData: the output folder is mounted as /tmp, where the JVM would leave its hsperfdata_root folder
docker run -u0 --rm -e "_JAVA_OPTIONS=-XX:-UsePerfData" -v "${output_folder}:/tmp" "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" \
    bash -c '/tmp/certs-create.sh "$1" "$2"; rc=$?; chown -R "$3" /tmp/; exit $rc' _ "${containers[*]}" "$new_open_ssl" "$(id -u):$(id -g)" > "$log_file" 2>&1
rc=$?
if [[ -n "$verbose" ]]
then
    grep -v "Picked up _JAVA_OPTIONS" "$log_file"
fi

missing=()
for container in "${containers[@]}"
do
    for f in "kafka.${container}.keystore.jks" "kafka.${container}.truststore.jks"
    do
        if [[ ! -s "${output_folder}/${f}" ]]
        then
            missing+=("$f")
        fi
    done
done
if [ $rc -ne 0 ] || [ ${#missing[@]} -gt 0 ]
then
    logerror "❌ the certificates could not be generated (exit code $rc${missing[*]:+, missing: ${missing[*]}}), end of the log:"
    grep -vE "Picked up _JAVA_OPTIONS|^[.+*-]+$" "$log_file" | tail -15 >&2
    exit 1
fi
ca_end=""
if command -v openssl > /dev/null 2>&1
then
    ca_end=$(openssl x509 -in "${output_folder}/snakeoil-ca-1.crt" -noout -enddate 2> /dev/null | sed 's/notAfter=/, valid until /')
fi
log "✅ keystores and truststores of ${containers[*]} (password: confluent), CA snakeoil-ca-1.crt${ca_end}"
