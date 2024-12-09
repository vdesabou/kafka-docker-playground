output_folder="${args[--output-folder]}"
verbose="${args[--verbose]}"
# Convert the space delimited string to an array
eval "containers=(${args[--container]})"

function cleanup {
    set +e
    rm -f "${output_folder}/certs-create.sh"
}
trap cleanup EXIT

maybe_redirect_output="> /dev/null 2>&1"
if [[ -n "$verbose" ]]
then
    maybe_redirect_output=""
fi

container_list="${containers[*]}"

new_open_ssl=0
if version_gt $CONNECT_TAG "7.7.99"
then
    new_open_ssl=1
fi
mkdir -p "${output_folder}"
cd "${output_folder}"
cp $root_folder/scripts/cli/src/ssl/certs-create.sh .
log "🔐 Generate keys and certificates in folder ${output_folder}"
docker run -u0 --rm -v $root_folder/scripts/cli/src/openssl.cnf:/usr/local/ssl/openssl.cnf -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "/tmp/certs-create.sh $maybe_redirect_output \"$container_list\" $new_open_ssl && chown -R $(id -u $USER):$(id -g $USER) /tmp/"