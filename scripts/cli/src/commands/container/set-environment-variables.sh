containers="${args[--container]}"
restore_original_values="${args[--restore-original-values]}"
mount_jscissors_files="${args[--mount-jscissors-files]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

# Convert the space delimited string to an array
eval "env_array=(${args[--env]})"

if [[ ! -n "$restore_original_values" ]]
then
    # check if env_array is empty
    if [ ${#env_array[@]} -eq 0 ]
    then
        logerror "❌ No environment variables provided with --env option"
        exit 1
    fi
fi

if [[ "$environment" == "cfk" ]]
then
    cfk_enable_jscissors_mount="false"
    if [[ -n "$mount_jscissors_files" ]]
    then
        cfk_enable_jscissors_mount="true"
    fi

    get_cfk_resource_for_pod() {
        local resolved_container=$1
        local pod_type
        local owner_name
        local resource_kind=""

        pod_type=$(kubectl -n confluent get pod "$resolved_container" -o jsonpath='{.metadata.labels.platform\.confluent\.io/type}' 2>/dev/null)
        if [[ -z "$pod_type" ]]
        then
            pod_type=$(kubectl -n confluent get pod "$resolved_container" -o jsonpath='{.metadata.labels.type}' 2>/dev/null)
        fi

        owner_name=$(kubectl -n confluent get pod "$resolved_container" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
        if [[ -z "$owner_name" ]]
        then
            owner_name="$resolved_container"
        fi

        case "$pod_type" in
            connect)
                resource_kind="connect"
                ;;
            kafka)
                resource_kind="kafka"
                ;;
            schemaregistry)
                resource_kind="schemaregistry"
                ;;
            controlcenter)
                resource_kind="controlcenter"
                ;;
            ksqldb)
                resource_kind="ksqldb"
                ;;
            zookeeper)
                resource_kind="zookeeper"
                ;;
            *)
                resource_kind=""
                ;;
        esac

        echo "$resource_kind:$owner_name"
    }

    build_updates_json() {
        local updates='[]'
        local env_variable
        local env_name
        local env_value

        for env_variable in "${env_array[@]}"
        do
            if [[ "$env_variable" != *":"* ]]
            then
                logerror "❌ Invalid --env format: $env_variable (expected NAME: VALUE)"
                exit 1
            fi

            env_name=$(echo "${env_variable%%:*}" | xargs)
            env_value=$(echo "${env_variable#*:}" | sed -E 's/^[[:space:]]+//')
            if [[ -z "$env_name" ]]
            then
                logerror "❌ Invalid --env format: $env_variable (empty variable name)"
                exit 1
            fi
            updates=$(echo "$updates" | jq -c --arg name "$env_name" --arg value "$env_value" '. + [{"name":$name,"value":$value}]')
        done

        echo "$updates"
    }

    import_image_into_local_cluster() {
        local local_image=$1
        local current_context

        current_context=$(kubectl config current-context 2>/dev/null)
        if command -v minikube >/dev/null 2>&1 && [[ "$current_context" == "minikube" ]]
        then
            log "📦 Loading image $local_image into minikube"
            if ! minikube image load "$local_image" > /tmp/pg-setenv-minikube-load.log 2>&1
            then
                logerror "❌ failed to load image $local_image into minikube"
                cat /tmp/pg-setenv-minikube-load.log
                exit 1
            fi
        elif command -v k3d >/dev/null 2>&1 && [[ "$current_context" == k3d-* ]]
        then
            k3d_cluster_name=${current_context#k3d-}
            log "📦 Importing image $local_image into k3d cluster $k3d_cluster_name"
            if ! k3d image import "$local_image" --cluster "$k3d_cluster_name" > /tmp/pg-setenv-k3d-import.log 2>&1
            then
                logerror "❌ failed to import image $local_image into k3d cluster $k3d_cluster_name"
                cat /tmp/pg-setenv-k3d-import.log
                exit 1
            fi
        else
            logwarn "⚠️ Not running on minikube/k3d context; ensure cluster nodes can pull image $local_image"
        fi
    }

    wait_for_cfk_pod_image_and_ready() {
        local resolved_container=$1
        local expected_image=$2
        local deadline=$((SECONDS + 600))

        while true
        do
            pod_image=$(kubectl -n confluent get pod "$resolved_container" -o jsonpath='{.spec.containers[?(@.name=="connect")].image}' 2>/dev/null)
            pod_ready=$(kubectl -n confluent get pod "$resolved_container" -o jsonpath='{.status.containerStatuses[?(@.name=="connect")].ready}' 2>/dev/null)
            if [[ "$pod_image" == "$expected_image" && "$pod_ready" == "true" ]]
            then
                return
            fi

            if (( SECONDS >= deadline ))
            then
                logerror "❌ timed out waiting for pod $resolved_container to roll out image $expected_image"
                logerror "Current connect image: ${pod_image:-unknown}, ready: ${pod_ready:-unknown}"
                exit 1
            fi

            sleep 5
        done
    }

    ensure_cfk_jscissors_files_image() {
        local resource_kind=$1
        local resource_name=$2
        local resolved_container=$3
        local state_image_backup_key="run.cfk.setenv.backup_image.${resource_kind}.${resource_name}"
        local current_image
        local existing_backup
        local local_image
        local build_dir
        local jar_source="/tmp/jscissors-1.0-SNAPSHOT.jar"
        local props_source="/tmp/scissors.props"

        if [[ "$resource_kind" != "connect" ]]
        then
            logerror "❌ --mount-jscissors-files in cfk mode currently supports connect only (got $resource_kind/$resource_name)"
            exit 1
        fi

        if [[ ! -f "$props_source" ]]
        then
            logerror "❌ missing $props_source"
            logerror "jscissors props file must exist before using --mount-jscissors-files in cfk mode"
            exit 1
        fi

        if [[ ! -f "$jar_source" ]]
        then
            jar_source="${root_folder}/scripts/cli/src/jscissors/jscissors-1.0-SNAPSHOT.jar"
        fi
        if [[ ! -f "$jar_source" ]]
        then
            logerror "❌ missing jscissors jar file in /tmp and in repository"
            exit 1
        fi

        current_image=$(kubectl -n confluent get "$resource_kind" "$resource_name" -o jsonpath='{.spec.image.application}' 2>/dev/null)
        if [[ -z "$current_image" ]]
        then
            logerror "❌ could not read current image from $resource_kind/$resource_name"
            exit 1
        fi

        existing_backup=$(playground state get "$state_image_backup_key")
        if [[ -z "$existing_backup" ]]
        then
            playground state set "$state_image_backup_key" "$current_image"
        fi

        local_image="playground-cfk-jscissors:$(date '+%Y%m%d%H%M%S')"
        build_dir=$(mktemp -d -t pg-cfk-jscissors-XXXXXXXXXX)
        cp "$jar_source" "$build_dir/jscissors-1.0-SNAPSHOT.jar"
        cp "$props_source" "$build_dir/scissors.props"

        cat << EOF > "$build_dir/Dockerfile"
FROM ${current_image}
USER root
COPY jscissors-1.0-SNAPSHOT.jar /tmp/jscissors-1.0-SNAPSHOT.jar
COPY scissors.props /tmp/scissors.props
RUN chown 1000:1000 /tmp/jscissors-1.0-SNAPSHOT.jar /tmp/scissors.props || true
USER 1000
EOF

        log "🏗️ Building CFK image with jscissors files from ${current_image}"
        if ! docker build -t "$local_image" "$build_dir" > /tmp/pg-setenv-jscissors-build.log 2>&1
        then
            logerror "❌ failed to build image $local_image"
            cat /tmp/pg-setenv-jscissors-build.log
            rm -rf "$build_dir"
            exit 1
        fi
        rm -rf "$build_dir"

        import_image_into_local_cluster "$local_image"

        log "☸️ Patching $resource_kind/$resource_name to use image $local_image"
        kubectl -n confluent patch "$resource_kind" "$resource_name" --type merge -p "{\"spec\":{\"image\":{\"application\":\"$local_image\"}}}" > /dev/null
        if [ $? -ne 0 ]
        then
            logerror "❌ failed to patch image for $resource_kind/$resource_name"
            exit 1
        fi

        wait_for_cfk_pod_image_and_ready "$resolved_container" "$local_image"
    }

    restore_cfk_original_image_if_needed() {
        local resource_kind=$1
        local resource_name=$2
        local resolved_container=$3
        local state_image_backup_key="run.cfk.setenv.backup_image.${resource_kind}.${resource_name}"
        local original_image

        original_image=$(playground state get "$state_image_backup_key")
        if [[ -z "$original_image" ]]
        then
            return
        fi

        log "🧽 restoring original image for $resource_kind/$resource_name"
        kubectl -n confluent patch "$resource_kind" "$resource_name" --type merge -p "{\"spec\":{\"image\":{\"application\":\"$original_image\"}}}" > /dev/null
        if [ $? -ne 0 ]
        then
            logerror "❌ failed to restore original image for $resource_kind/$resource_name"
            exit 1
        fi

        wait_for_cfk_pod_image_and_ready "$resolved_container" "$original_image"
        playground state del "$state_image_backup_key"
    }

    declare -A cfk_processed_resources
    if [[ -z "$restore_original_values" ]]
    then
        updates_json=$(build_updates_json)
    fi

    for container in "${container_array[@]}"
    do
        resolved_container=$(resolve_container_name_for_environment "$container")
        resource_ref=$(get_cfk_resource_for_pod "$resolved_container")
        resource_kind=${resource_ref%%:*}
        resource_name=${resource_ref#*:}

        if [[ -z "$resource_kind" || -z "$resource_name" ]]
        then
            logerror "❌ Could not resolve CFK resource for container/pod $resolved_container"
            exit 1
        fi

        resource_key="$resource_kind/$resource_name"
        if [[ "${cfk_processed_resources[$resource_key]}" == "1" ]]
        then
            continue
        fi

        state_backup_key="run.cfk.setenv.backup.${resource_kind}.${resource_name}"
        current_env_json=$(kubectl -n confluent get "$resource_kind" "$resource_name" -o json | jq -c '.spec.podTemplate.envVars // []')
        if [ $? -ne 0 ]
        then
            logerror "❌ failed to read current env from $resource_kind/$resource_name"
            exit 1
        fi

        if [[ -n "$restore_original_values" ]]
        then
            backup_env_json=$(playground state get "$state_backup_key")
            if [[ -z "$backup_env_json" ]]
            then
                logwarn "⚠️ no backup env found for $resource_kind/$resource_name, skipping restore"
                restore_cfk_original_image_if_needed "$resource_kind" "$resource_name" "$resolved_container"
                cfk_processed_resources[$resource_key]="1"
                continue
            fi

            patch_payload=$(jq -cn --argjson env "$backup_env_json" '{"spec":{"podTemplate":{"envVars":$env}}}')
            log "🧽 restoring original env vars for $resource_kind/$resource_name"
            kubectl -n confluent patch "$resource_kind" "$resource_name" --type merge -p "$patch_payload" > /dev/null
            if [ $? -ne 0 ]
            then
                logerror "❌ failed to restore env vars for $resource_kind/$resource_name"
                exit 1
            fi
            playground state del "$state_backup_key"
            restore_cfk_original_image_if_needed "$resource_kind" "$resource_name" "$resolved_container"
        else
            if [[ "$cfk_enable_jscissors_mount" == "true" ]]
            then
                ensure_cfk_jscissors_files_image "$resource_kind" "$resource_name" "$resolved_container"
            fi

            existing_backup=$(playground state get "$state_backup_key")
            if [[ -z "$existing_backup" ]]
            then
                playground state set "$state_backup_key" "$current_env_json"
            fi

            merged_env_json=$(echo "$current_env_json" | jq -c --argjson updates "$updates_json" '
                reduce $updates[] as $u (.;
                    if any(.[]; .name == $u.name) then
                        map(if .name == $u.name then {"name":$u.name,"value":$u.value} else . end)
                    else
                        . + [{"name":$u.name,"value":$u.value}]
                    end
                )
            ')
            patch_payload=$(jq -cn --argjson env "$merged_env_json" '{"spec":{"podTemplate":{"envVars":$env}}}')
            log "📦 enabling containers ${containers} with environment variables ${env_array[*]} on $resource_kind/$resource_name"
            kubectl -n confluent patch "$resource_kind" "$resource_name" --type merge -p "$patch_payload" > /dev/null
            if [ $? -ne 0 ]
            then
                logerror "❌ failed to patch env vars on $resource_kind/$resource_name"
                exit 1
            fi
        fi

        log "⌛ Waiting for pod $resolved_container to be ready after env update"
        if ! kubectl -n confluent wait --for=condition=Ready "pod/$resolved_container" --timeout=300s > /dev/null 2>&1
        then
            logerror "❌ pod $resolved_container did not become ready after env update"
            kubectl -n confluent get pods
            exit 1
        fi

        cfk_processed_resources[$resource_key]="1"
    done

    exit 0
fi

# For ccloud case
if [ -f $root_folder/.ccloud/env.delta ]
then
     source $root_folder/.ccloud/env.delta
fi

# keep TAG, CONNECT TAG and ORACLE_IMAGE
export TAG=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
export CP_CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)

docker_command=$(playground state get run.docker_command)
if [ "$docker_command" == "" ]
then
  logerror "docker_command retrieved from $root_folder/playground.ini is empty !"
  exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

if [[ ! -n "$restore_original_values" ]]
then
    cat << EOF > $tmp_dir/docker-compose.override.java.env.yml
services:
EOF

    # Generate environment variables for each container
    for container in "${container_array[@]}"
    do
                resolved_container=$(resolve_container_name_for_environment "$container")
        cat << EOF >> $tmp_dir/docker-compose.override.java.env.yml
    $resolved_container:
    environment:
      DUMMY: $RANDOM
EOF

        for env_variable in "${env_array[@]}"
        do
            env_list="$env_list $env_variable"
            cat << EOF >> $tmp_dir/docker-compose.override.java.env.yml
      $env_variable
EOF
        done

        if [[ -n "$mount_jscissors_files" ]]
        then
            cat << EOF >> $tmp_dir/docker-compose.override.java.env.yml
    volumes:
      - /tmp/:/tmp/
EOF
        fi
    done

    log "📦 enabling containers ${containers} with environment variables $env_list"
    echo "$docker_command" > $tmp_dir/playground-command-java-env
    sed -i -E -e "s|up -d --quiet-pull|-f $tmp_dir/docker-compose.override.java.env.yml up -d --quiet-pull|g" $tmp_dir/playground-command-java-env
    load_env_variables
    bash $tmp_dir/playground-command-java-env
else
    log "🧽 restore back original values before any changes was made for containers ${containers}"
    echo "$docker_command" > $tmp_dir/playground-command
    load_env_variables
    bash $tmp_dir/playground-command
fi
wait_container_ready


test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

if [[ "${test_file}" == *"xstream"* ]]
then
    log "💫 xstream test detected, re-installing libraries..."
    # https://github.com/confluentinc/common-docker/pull/743 and https://github.com/adoptium/adoptium-support/issues/1285
    set +e
    playground container exec --root --command 'sed -i "s/packages\.adoptium\.net/adoptium\.jfrog\.io/g" /etc/yum.repos.d/adoptium.repo'
    playground container exec --root --command "microdnf -y install libaio"

    if [ "$(uname -m)" = "arm64" ]
    then
        :
    else
        if version_gt $TAG_BASE "7.9.9"
        then
            playground container exec --root --command "microdnf -y install libnsl2"
            playground container exec --root --command "ln -s /usr/lib64/libnsl.so.3 /usr/lib64/libnsl.so.1"
        else
            playground container exec --root --command "ln -s /usr/lib64/libnsl.so.2 /usr/lib64/libnsl.so.1"
        fi
    fi
fi