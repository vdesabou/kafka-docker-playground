# helpers of 'playground storage ls|cat|wait-for-objects' (and the object store sinks of 'connector reconcile'):
# one rclone container reaches the object store of a sink connector (S3, MinIO and other S3 compatible stores, GCS,
# Azure Blob Storage, ADLS Gen2, HDFS, SFTP), configured with RCLONE_CONFIG_SRC_* environment variables, so no
# provider command line (aws, gcloud, az, hdfs dfs, sftp) is needed

STORAGE_RCLONE_IMAGE="rclone/rclone:latest"

# value of the first key set in $storage_config (empty values count as not set)
function storage_cfg () {
    local key value
    for key in "$@"
    do
        value=$(jq -r --arg k "$key" '.[$k] // empty | tostring' <<< "$storage_config" 2>/dev/null)
        if [[ -n "$value" ]]
        then
            echo "$value"
            return 0
        fi
    done
}

function storage_is_masked () {
    [[ -z "$1" || "$1" == *"•"* || "$1" =~ ^\*+$ || "$1" == "[hidden]" ]]
}

# the literal value of a key in the example script that was run (a secret masked by the REST API)
function storage_literal_in_test_file () {
    local key="$1" test_file
    test_file=$(playground state get run.test_file 2>/dev/null)
    [[ -f "$test_file" ]] || return 0
    grep -o -E "\"${key//./\\.}\"[[:space:]]*:[[:space:]]*\"[^\"\$]*\"" "$test_file" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/'
}

# a file of the connect container (key file, credentials, config provider file), empty when there is none
function storage_connect_file () {
    local file="$1"
    [[ -n "$storage_connect_container" ]] || return 0
    docker exec "$storage_connect_container" cat "$file" 2>/dev/null
}

# usable value of a connector config key: literal, ${file:<path>:<key>} resolved in the connect container, or the
# literal of the example script when the REST API masks it; empty when none works
function storage_secret () {
    local key value path name
    for key in "$@"
    do
        value=$(storage_cfg "$key")
        [[ -z "$value" ]] && continue
        if [[ "$value" =~ ^\$\{file:([^:}]+):([^}]+)\}$ ]]
        then
            path="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            value=$(storage_connect_file "$path" | grep -E "^[[:space:]]*${name}[[:space:]]*[=:]" | head -1 | sed -E 's/^[^=:]*[=:][[:space:]]*//' | tr -d '\r')
        elif [[ "$value" == *'${'* ]]
        then
            value=""
        elif storage_is_masked "$value"
        then
            value=$(storage_literal_in_test_file "$key")
        fi
        if [[ -n "$value" ]]
        then
            echo "$value"
            return 0
        fi
    done
}

# the docker network to run rclone on: the network of the container named <host> (minio, namenode, sftp-server...),
# else the network namespace of connect (its view of the names), else the default network (cloud stores)
function storage_network_for_host () {
    local host="$1" network=""
    if [[ -n "$host" ]] && docker inspect "$host" > /dev/null 2>&1
    then
        network=$(docker inspect "$host" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | awk '{print $1}')
    fi
    if [[ -n "$network" ]]
    then
        storage_docker_args+=(--network "$network")
    elif [[ -n "$storage_connect_container" && -n "$host" && "$host" != *.* ]]
    then
        storage_docker_args+=(--network "container:$storage_connect_container")
    fi
}

function storage_env () {
    storage_docker_args+=(-e "RCLONE_CONFIG_SRC_$1=$2")
}

function storage_aws_credentials () {
    local access secret token="" creds
    access=$(storage_secret aws.access.key.id)
    secret=$(storage_secret aws.secret.access.key)
    if [[ -z "$access" || -z "$secret" ]]
    then
        # default credentials provider chain of the connector: the credentials file of the connect container
        # (/tmp/aws_credentials of handle_aws_credentials, the MinIO example...)
        creds=$(storage_connect_file "$(storage_cfg aws.credentials.file)")
        [[ -z "$creds" ]] && creds=$(storage_connect_file "/tmp/aws_credentials")
        [[ -z "$creds" ]] && creds=$(docker exec "${storage_connect_container:-none}" sh -c 'cat $HOME/.aws/credentials' 2>/dev/null)
        if [[ -n "$creds" ]]
        then
            access=$(grep -i -m1 '^[[:space:]]*aws_access_key_id' <<< "$creds" | sed -E 's/^[^=]*=[[:space:]]*//' | tr -d '\r ')
            secret=$(grep -i -m1 '^[[:space:]]*aws_secret_access_key' <<< "$creds" | sed -E 's/^[^=]*=[[:space:]]*//' | tr -d '\r ')
            token=$(grep -i -m1 '^[[:space:]]*aws_session_token' <<< "$creds" | sed -E 's/^[^=]*=[[:space:]]*//' | tr -d '\r ')
        fi
    fi
    if [[ -z "$access" || -z "$secret" ]]
    then
        if [[ -z "$AWS_ACCESS_KEY_ID" ]] && type load_secrets_env_vars > /dev/null 2>&1
        then
            load_secrets_env_vars AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION > /dev/null 2>&1
        fi
        if [[ -z "$AWS_ACCESS_KEY_ID" && -f "$HOME/.aws/credentials" ]]
        then
            AWS_ACCESS_KEY_ID=$(grep -m1 "^aws_access_key_id" "$HOME/.aws/credentials" | awk -F'=' '{print $2}' | tr -d ' ')
            AWS_SECRET_ACCESS_KEY=$(grep -m1 "^aws_secret_access_key" "$HOME/.aws/credentials" | awk -F'=' '{print $2}' | tr -d ' ')
        fi
        access="$AWS_ACCESS_KEY_ID"
        secret="$AWS_SECRET_ACCESS_KEY"
        token="$AWS_SESSION_TOKEN"
        storage_credentials_origin="AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY"
    else
        storage_credentials_origin="the connector"
    fi
    if [[ -z "$access" || -z "$secret" ]]
    then
        logerror "❌ no AWS credentials: not in the connector config, nor AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, nor ~/.aws/credentials"
        return 1
    fi
    storage_env ACCESS_KEY_ID "$access"
    storage_env SECRET_ACCESS_KEY "$secret"
    [[ -n "$token" ]] && storage_env SESSION_TOKEN "$token"
    return 0
}

function storage_gcp_credentials () {
    local json path
    json=$(storage_secret gcs.credentials.json gcs.credentials.config)
    if [[ -z "$json" ]]
    then
        path=$(storage_cfg gcs.credentials.path)
        [[ -n "$path" ]] && json=$(storage_connect_file "$path")
    fi
    storage_credentials_origin="the connector"
    if [[ -z "$json" ]]
    then
        if [[ -z "$GCP_KEYFILE_CONTENT" ]] && type load_secrets_env_vars > /dev/null 2>&1
        then
            load_secrets_env_vars GCP_KEYFILE_CONTENT > /dev/null 2>&1
        fi
        if [[ -n "$GCP_KEYFILE_CONTENT" ]]
        then
            json="$GCP_KEYFILE_CONTENT"
            # the json as is, or as the examples store it (escaped by jq -aRs, without the quotes)
            if ! jq -e .type > /dev/null 2>&1 <<< "$json"
            then
                json=$(echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g')
            fi
            storage_credentials_origin="GCP_KEYFILE_CONTENT"
        elif [[ -n "$GCP_KEYFILE" && -f "$GCP_KEYFILE" ]]
        then
            json=$(cat "$GCP_KEYFILE")
            storage_credentials_origin="GCP_KEYFILE"
        fi
    fi
    if ! jq -e '.type' > /dev/null 2>&1 <<< "$json"
    then
        logerror "❌ no GCP service account key: not in the connector config (gcs.credentials.path / json), nor GCP_KEYFILE_CONTENT"
        return 1
    fi
    storage_env SERVICE_ACCOUNT_CREDENTIALS "$(jq -c . <<< "$json")"
    storage_env BUCKET_POLICY_ONLY "true"
}

# parse a --url: s3://bucket/prefix, gs://bucket/prefix, az://account/container/prefix, hdfs://[user@]namenode:port/path,
# sftp://[user[:password]@]host[:port]/path
function storage_resolve_url () {
    local url="$1" endpoint="$2" scheme rest userinfo hostport
    scheme="${url%%://*}"
    rest="${url#*://}"
    case "$scheme" in
        s3|minio)
            storage_provider="s3"
            storage_bucket="${rest%%/*}"
            [[ "$rest" == */* ]] && storage_prefix="${rest#*/}"
            storage_config='{}'
            storage_aws_credentials || return 1
            storage_env TYPE s3
            if [[ -n "$endpoint" ]]
            then
                storage_env PROVIDER Other
                storage_env ENDPOINT "$endpoint"
                storage_env FORCE_PATH_STYLE true
                hostport="${endpoint#*://}"
                storage_network_for_host "${hostport%%[:/]*}"
            else
                storage_env PROVIDER AWS
                storage_env REGION "${AWS_REGION:-us-east-1}"
            fi
        ;;
        gs|gcs)
            storage_provider="gcs"
            storage_bucket="${rest%%/*}"
            [[ "$rest" == */* ]] && storage_prefix="${rest#*/}"
            storage_config='{}'
            storage_gcp_credentials || return 1
            storage_env TYPE "google cloud storage"
        ;;
        az|azure|abfs|abfss)
            storage_provider="azure"
            local account="${rest%%/*}"
            rest="${rest#*/}"
            storage_bucket="${rest%%/*}"
            [[ "$rest" == */* ]] && storage_prefix="${rest#*/}"
            if [[ -z "$AZURE_ACCOUNT_KEY" ]] && type load_secrets_env_vars > /dev/null 2>&1
            then
                load_secrets_env_vars AZURE_ACCOUNT_KEY > /dev/null 2>&1
            fi
            if [[ -z "$AZURE_ACCOUNT_KEY" ]]
            then
                logerror "❌ set AZURE_ACCOUNT_KEY to the key of storage account $account (az storage account keys list)"
                return 1
            fi
            storage_credentials_origin="AZURE_ACCOUNT_KEY"
            storage_env TYPE azureblob
            storage_env ACCOUNT "$account"
            storage_env KEY "$AZURE_ACCOUNT_KEY"
        ;;
        hdfs|webhdfs)
            storage_provider="hdfs"
            hostport="${rest%%/*}"
            userinfo="root"
            if [[ "$hostport" == *@* ]]
            then
                userinfo="${hostport%%@*}"
                hostport="${hostport#*@}"
            fi
            storage_bucket=""
            storage_prefix="/${rest#*/}"
            [[ "$rest" != */* ]] && storage_prefix="/"
            storage_env TYPE hdfs
            storage_env NAMENODE "$hostport"
            storage_env USERNAME "$userinfo"
            storage_credentials_origin="user $userinfo"
            storage_network_for_host "${hostport%%:*}"
        ;;
        sftp)
            storage_provider="sftp"
            hostport="${rest%%/*}"
            local user="" password=""
            if [[ "$hostport" == *@* ]]
            then
                userinfo="${hostport%%@*}"
                hostport="${hostport#*@}"
                user="${userinfo%%:*}"
                [[ "$userinfo" == *:* ]] && password="${userinfo#*:}"
            fi
            storage_bucket=""
            storage_prefix="/${rest#*/}"
            [[ "$rest" != */* ]] && storage_prefix="/"
            storage_env TYPE sftp
            storage_env KNOWN_HOSTS_FILE none
            storage_env HOST "${hostport%%:*}"
            [[ "$hostport" == *:* ]] && storage_env PORT "${hostport#*:}"
            [[ -n "$user" ]] && storage_env USER "$user"
            storage_sftp_password="$password"
            storage_credentials_origin="user ${user:-?}"
            storage_network_for_host "${hostport%%:*}"
        ;;
        *)
            logerror "❌ --url $url: use s3://, gs://, az://<account>/<container>, hdfs:// or sftp://"
            return 1
        ;;
    esac
    # never print a password of the url
    storage_label=$(sed -E 's#://([^:/@]+):[^@/]*@#://\1:***@#' <<< "$url")
}

# from the config of a sink (or source) connector of an object store
function storage_resolve_connector () {
    local class class_lc topics_dir endpoint host region
    class=$(storage_cfg connector.class)
    class_lc="${class,,}"
    topics_dir=$(storage_cfg topics.dir)
    case "$class_lc" in
        *hdfs*)
            storage_provider="hdfs"
            local url user
            url=$(storage_cfg hdfs.url store.url)
            user=$(storage_cfg hdfs.authentication.kerberos)
            if [[ "$user" == "true" ]]
            then
                logwarn "⚠️ Kerberos is enabled on the connector: rclone connects without Kerberos, which a secured cluster refuses"
            fi
            host="${url#*://}"
            host="${host%%/*}"
            storage_bucket=""
            storage_prefix="/${topics_dir:-topics}"
            storage_prefix="${storage_prefix//\/\//\/}"
            storage_env TYPE hdfs
            storage_env NAMENODE "$host"
            storage_env USERNAME "${HADOOP_USER_NAME:-root}"
            storage_credentials_origin="user ${HADOOP_USER_NAME:-root}"
            storage_network_for_host "${host%%:*}"
        ;;
        *s3*)
            storage_provider="s3"
            storage_bucket=$(storage_cfg s3.bucket.name)
            storage_prefix="${topics_dir:-topics}"
            storage_aws_credentials || return 1
            storage_env TYPE s3
            endpoint=$(storage_cfg store.url aws.s3.endpoint)
            region=$(storage_cfg s3.region)
            if [[ -n "$endpoint" ]]
            then
                storage_env PROVIDER Other
                storage_env ENDPOINT "$endpoint"
                storage_env FORCE_PATH_STYLE true
                host="${endpoint#*://}"
                storage_network_for_host "${host%%[:/]*}"
            else
                storage_env PROVIDER AWS
                storage_env REGION "${region:-${AWS_REGION:-us-east-1}}"
            fi
        ;;
        *gcs*|*googlecloudstorage*)
            storage_provider="gcs"
            storage_bucket=$(storage_cfg gcs.bucket.name)
            storage_prefix="${topics_dir:-topics}"
            storage_gcp_credentials || return 1
            storage_env TYPE "google cloud storage"
        ;;
        *azure.blob*|*azureblob*|*datalake*|*adls*)
            storage_provider="azure"
            local account key client_id client_secret tenant endpoint_url
            if [[ "$class_lc" == *datalake* || "$class_lc" == *adls* ]]
            then
                account=$(storage_secret azure.datalake.gen2.account.name azure.datalake.account.name)
                key=$(storage_secret azure.datalake.gen2.access.key)
                client_id=$(storage_secret azure.datalake.gen2.client.id azure.datalake.client.id)
                client_secret=$(storage_secret azure.datalake.gen2.client.key azure.datalake.client.key)
                endpoint_url=$(storage_secret azure.datalake.gen2.token.endpoint azure.datalake.token.endpoint)
                # the ADLS Gen2 sink writes to the file system named after the first folder of topics.dir ("topics"
                # by default), at its root: topics/<topic>/partition=0/...
                local dir="${topics_dir:-topics}"
                dir="${dir#/}"
                storage_bucket="${dir%%/*}"
                storage_datalake_prefix=""
                [[ "$dir" == */* ]] && storage_datalake_prefix="${dir#*/}"
            else
                account=$(storage_secret azblob.account.name)
                key=$(storage_secret azblob.account.key)
                storage_bucket=$(storage_secret azblob.container.name)
                storage_bucket="${storage_bucket:-default}"
            fi
            storage_prefix="${topics_dir:-topics}"
            if [[ "$class_lc" == *datalake* || "$class_lc" == *adls* ]]
            then
                storage_prefix="$storage_datalake_prefix"
            fi
            if [[ -z "$key" && -z "$client_secret" ]]
            then
                if [[ -z "$AZURE_ACCOUNT_KEY" ]] && type load_secrets_env_vars > /dev/null 2>&1
                then
                    load_secrets_env_vars AZURE_ACCOUNT_KEY > /dev/null 2>&1
                fi
                key="$AZURE_ACCOUNT_KEY"
                storage_credentials_origin="AZURE_ACCOUNT_KEY"
            else
                storage_credentials_origin="the connector"
            fi
            if [[ -z "$account" ]] || [[ -z "$key" && -z "$client_secret" ]]
            then
                logerror "❌ could not get the storage account and its key (or service principal) from the connector config: use --url az://<account>/<container> with AZURE_ACCOUNT_KEY"
                return 1
            fi
            storage_azure_account="$account"
            storage_env TYPE azureblob
            storage_env ACCOUNT "$account"
            if [[ -n "$key" ]]
            then
                storage_env KEY "$key"
            else
                # https://login.microsoftonline.com/<tenant>/oauth2/token
                tenant=$(sed -E 's#^https?://[^/]+/([^/]+)/.*#\1#' <<< "$endpoint_url")
                storage_env TENANT "$tenant"
                storage_env CLIENT_ID "$client_id"
                storage_env CLIENT_SECRET "$client_secret"
            fi
        ;;
        *sftp*)
            storage_provider="sftp"
            local sftp_host port user password key_path
            sftp_host=$(storage_cfg sftp.host)
            port=$(storage_cfg sftp.port)
            user=$(storage_cfg sftp.username)
            password=$(storage_secret sftp.password)
            key_path=$(storage_cfg tls.private.key)
            storage_bucket=""
            storage_prefix=$(storage_cfg sftp.working.dir)
            storage_prefix="${storage_prefix:-/}"
            storage_env TYPE sftp
            storage_env KNOWN_HOSTS_FILE none
            storage_env HOST "$sftp_host"
            [[ -n "$port" ]] && storage_env PORT "$port"
            [[ -n "$user" ]] && storage_env USER "$user"
            if [[ -z "$password" && -n "$key_path" ]]
            then
                logwarn "⚠️ the connector authenticates with a private key: pass --url sftp://user:password@host/path if the server also accepts a password"
            fi
            storage_sftp_password="$password"
            storage_credentials_origin="user ${user:-?}"
            storage_network_for_host "$sftp_host"
        ;;
        *)
            logerror "❌ connector class $class is not an object store connector (S3, GCS, Azure Blob, ADLS Gen2, HDFS, SFTP): use --url"
            return 1
        ;;
    esac
    if [[ "$storage_provider" =~ ^(s3|gcs|azure)$ && -z "$storage_bucket" ]]
    then
        logerror "❌ could not get the bucket / container from the config of connector $storage_connector: use --url"
        return 1
    fi
    case "$storage_provider" in
        s3) storage_label="s3://$storage_bucket/${storage_prefix#/}" ;;
        gcs) storage_label="gs://$storage_bucket/${storage_prefix#/}" ;;
        azure) storage_label="az://$storage_azure_account/$storage_bucket/${storage_prefix#/}" ;;
        hdfs) storage_label="$(storage_cfg hdfs.url store.url)${storage_prefix}" ;;
        sftp) storage_label="sftp://$(storage_cfg sftp.host)${storage_prefix}" ;;
    esac
    return 0
}

# is a connector class (lower case) a sink of an object store that 'playground storage' reads?
function storage_is_object_store_sink () {
    local class_lc="$1"
    [[ "$class_lc" == *source* ]] && return 1
    [[ "$class_lc" == *hdfs* || "$class_lc" == *s3* || "$class_lc" == *gcs* || "$class_lc" == *googlecloudstorage* \
        || "$class_lc" == *azure.blob* || "$class_lc" == *azureblob* || "$class_lc" == *datalake* || "$class_lc" == *adls* \
        || "$class_lc" == *sftp* ]]
}

# set storage_provider, storage_bucket, storage_prefix, storage_label and storage_docker_args (the rclone container) from
# --url, or from the config of --connector (the only running connector when neither is given):
#   storage_resolve <connector> <url> <endpoint> <prefix override>
function storage_resolve () {
    local connector="$1" url="$2" endpoint="$3" prefix="$4"
    storage_docker_args=()
    storage_provider="" storage_bucket="" storage_prefix="" storage_azure_account="" storage_label="" storage_sftp_password=""
    storage_credentials_origin="" storage_connector="" storage_config='{}'
    storage_connect_container=""
    if docker inspect connect > /dev/null 2>&1
    then
        storage_connect_container="connect"
    fi

    if [[ -n "$url" ]]
    then
        storage_resolve_url "$url" "$endpoint" || return 1
    else
        if [[ -z "$connector" ]]
        then
            connector=$(playground get-connector-list 2>/dev/null)
            if [[ -z "$connector" ]]
            then
                logerror "💤 no connector is running: pass --url (s3://bucket/prefix, gs://, az://, hdfs://, sftp://)"
                return 1
            fi
            if [[ $(echo "$connector" | wc -w) -gt 1 ]]
            then
                logerror "❌ several connectors are running ($(echo $connector)): pass --connector"
                return 1
            fi
        fi
        storage_connector="$connector"
        if ! get_connector_config_json "$connector"
        then
            logerror "❌ could not get the config of connector $connector"
            return 1
        fi
        storage_config="$curl_output"
        local connector_type
        connector_type=$(playground state get run.connector_type)
        if [[ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" || "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]]
        then
            # the connector runs in Confluent Cloud: nothing to read in a local connect container
            storage_connect_container=""
        fi
        storage_resolve_connector || return 1
    fi
    if [[ -n "$prefix" ]]
    then
        storage_prefix="$prefix"
    fi
    storage_prefix="${storage_prefix%/}"
}

# rclone path of the base folder
function storage_remote_path () {
    local path="$storage_prefix"
    if [[ -n "$storage_bucket" ]]
    then
        echo "src:${storage_bucket}${path:+/${path#/}}"
    else
        echo "src:${path:-/}"
    fi
}

# run rclone with the configuration of storage_resolve: storage_rclone <rclone args>
# (STORAGE_RCLONE_VOLUME=<host dir> mounts that folder on /work)
function storage_rclone () {
    local extra=()
    if [[ -n "$STORAGE_RCLONE_VOLUME" ]]
    then
        extra=(-v "$(host_path "$STORAGE_RCLONE_VOLUME"):/work")
    fi
    # the sftp password must be obscured by rclone itself
    docker run --quiet --rm -i "${storage_docker_args[@]}" "${extra[@]}" \
        -e "STORAGE_SFTP_PASSWORD=$storage_sftp_password" -e RCLONE_CONFIG=/dev/null \
        --entrypoint sh "$STORAGE_RCLONE_IMAGE" \
        -c 'if [ -n "$STORAGE_SFTP_PASSWORD" ]; then RCLONE_CONFIG_SRC_PASS=$(rclone obscure "$STORAGE_SFTP_PASSWORD"); export RCLONE_CONFIG_SRC_PASS; fi; exec rclone "$@"' \
        rclone "$@"
}

# list the objects (files) under the base folder as rclone lsjson: storage_list <output file>
function storage_list () {
    local out="$1" err
    err=$(mktemp -t pg-storage-err-XXXXXXXXXX)
    if ! storage_rclone lsjson -R --files-only --no-mimetype "$(storage_remote_path)" > "$out" 2> "$err"
    then
        # S3, GCS and Azure have no folders: a missing prefix is an empty listing, "directory not found" is a missing
        # bucket. On HDFS and SFTP, the folder is created by the connector with its first file
        if grep -q -i "directory not found" "$err"
        then
            if [[ "$storage_provider" =~ ^(hdfs|sftp)$ ]]
            then
                echo "[]" > "$out"
                rm -f "$err"
                return 0
            fi
            logerror "❌ bucket / container $storage_bucket does not exist${storage_credentials_origin:+ (or is not visible with the credentials of $storage_credentials_origin)}"
            rm -f "$err"
            return 1
        fi
        logerror "❌ could not list $storage_label:"
        grep -v '^\s*$' "$err" | tail -5 >&2
        if grep -q -i -E "NoSuchBucket|bucket.*(does not exist|not found)|ContainerNotFound" "$err"
        then
            logerror "   🪣 the bucket / container does not exist"
        elif grep -q -i -E "AccessDenied|Forbidden|403|AuthorizationPermissionMismatch|InvalidAccessKeyId|SignatureDoesNotMatch|AuthenticationFailed|unable to authenticate|handshake failed|Permission denied" "$err"
        then
            logerror "   🔐 access denied with the credentials of $storage_credentials_origin"
        fi
        rm -f "$err"
        return 1
    fi
    rm -f "$err"
}

# remove a temp folder that the rclone / avro-tools / parquet-tools containers wrote to: on Linux their files belong to
# root (docker) or to a sub uid (rootless podman), so the host rm is refused; a container removes them. Never fails:
# it runs in the EXIT trap, whose status becomes the exit code of the command
function storage_remove_tmp_dir () {
    local dir="$1"
    [[ -n "$dir" && -d "$dir" ]] || return 0
    if ! rm -rf "$dir" 2> /dev/null
    then
        docker run --quiet --rm -v "$(host_path "$dir"):/work" --entrypoint sh "$STORAGE_RCLONE_IMAGE" \
            -c 'rm -rf /work/* /work/.[!.]* 2> /dev/null; true' > /dev/null 2>&1
        rm -rf "$dir" 2> /dev/null
    fi
    return 0
}

function storage_show_target () {
    log "🪣 ${storage_label}${storage_connector:+ (connector $storage_connector)}${storage_credentials_origin:+, credentials of $storage_credentials_origin}"
}
