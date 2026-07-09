containers="${args[--container]}"
version="${args[--version]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    resolved_container=$(resolve_container_name_for_environment "$container")
    if [[ "$environment" == "cfk" ]]
    then
        if [[ ! "$resolved_container" =~ ^connect(-[0-9]+)?$ ]]
        then
            logerror "❌ persistent change-jdk in cfk mode currently supports Connect pods only (got: $resolved_container)"
            exit 1
        fi

        current_image=$(kubectl -n confluent get connect connect -o jsonpath='{.spec.image.application}' 2>/dev/null)
        if [[ -z "$current_image" ]]
        then
            logerror "❌ could not read current Connect image from Connect CR"
            exit 1
        fi

        local_image="playground-connect-zulu${version}:$(date '+%Y%m%d%H%M%S')"
        build_dir=$(mktemp -d -t pg-jdk-build-XXXXXXXXXX)

        log "🏗️ Building persistent CFK Connect image with JDK ${version} from ${current_image}"
        cat << EOF > "$build_dir/Dockerfile"
FROM ${current_image}
USER root
RUN if command -v microdnf >/dev/null 2>&1; then microdnf -y install yum; fi \
 && yum install -y https://cdn.azul.com/zulu/bin/zulu-repo-1.0.0-1.noarch.rpm \
 && yum -y install zulu${version}-jdk \
 && java_candidate=\$(update-alternatives --display java 2>/dev/null | awk '/java-${version}-zulu-openjdk/ && /priority/ {print \$1; exit}') \
 && if [ -z "\$java_candidate" ]; then echo "Could not resolve java alternative for zulu${version}" >&2; exit 1; fi \
 && update-alternatives --set java "\$java_candidate" \
 && javac_candidate=\$(update-alternatives --display javac 2>/dev/null | awk '/java-${version}-zulu-openjdk/ && /priority/ {print \$1; exit}') \
 && if [ -n "\$javac_candidate" ]; then update-alternatives --set javac "\$javac_candidate"; fi \
 && yum clean all \
 && rm -rf /var/cache/yum
USER 1000
EOF

        if ! docker build -t "$local_image" "$build_dir" > /tmp/pg-change-jdk-build.log 2>&1
        then
            logerror "❌ failed to build persistent Connect image $local_image"
            cat /tmp/pg-change-jdk-build.log
            rm -rf "$build_dir"
            exit 1
        fi
        rm -rf "$build_dir"

        current_context=$(kubectl config current-context 2>/dev/null)
        if command -v minikube >/dev/null 2>&1 && [[ "$current_context" == "minikube" ]]
        then
            log "📦 Loading image $local_image into minikube"
            if ! minikube image load "$local_image" > /tmp/pg-change-jdk-minikube-load.log 2>&1
            then
                logerror "❌ failed to load image $local_image into minikube"
                cat /tmp/pg-change-jdk-minikube-load.log
                exit 1
            fi
        elif command -v k3d >/dev/null 2>&1 && [[ "$current_context" == k3d-* ]]
        then
            k3d_cluster_name=${current_context#k3d-}
            log "📦 Importing image $local_image into k3d cluster $k3d_cluster_name"
            if ! k3d image import "$local_image" --cluster "$k3d_cluster_name" > /tmp/pg-change-jdk-k3d-import.log 2>&1
            then
                logerror "❌ failed to import image $local_image into k3d cluster $k3d_cluster_name"
                cat /tmp/pg-change-jdk-k3d-import.log
                exit 1
            fi
        else
            logwarn "⚠️ Not running on minikube/k3d context; ensure cluster nodes can pull image $local_image"
        fi

        log "☸️ Patching Connect CR to use image $local_image"
        patch_stderr=$(mktemp -t pg-cfk-patch-XXXXXXXXXX)
        kubectl -n confluent patch connect connect --type merge -p "{\"spec\":{\"image\":{\"application\":\"$local_image\"}}}" > /dev/null 2>"$patch_stderr"
        if [ $? -ne 0 ]
        then
            logerror "❌ failed to patch Connect CR image"
            cat "$patch_stderr"
            rm -f "$patch_stderr"
            exit 1
        fi
        rm -f "$patch_stderr"

        log "⌛ Waiting for pod $resolved_container to run image $local_image and be ready"
        rollout_deadline=$((SECONDS + 600))
        while true
        do
            pod_image=$(kubectl -n confluent get pod "$resolved_container" -o jsonpath='{.spec.containers[?(@.name=="connect")].image}' 2>/dev/null)
            pod_ready=$(kubectl -n confluent get pod "$resolved_container" -o jsonpath='{.status.containerStatuses[?(@.name=="connect")].ready}' 2>/dev/null)

            if [[ "$pod_image" == "$local_image" && "$pod_ready" == "true" ]]
            then
                break
            fi

            if (( SECONDS >= rollout_deadline ))
            then
                logerror "❌ timed out waiting for pod $resolved_container to roll out image $local_image"
                logerror "Current connect image: ${pod_image:-unknown}, ready: ${pod_ready:-unknown}"
                kubectl -n confluent get pod "$resolved_container" -o wide || true
                exit 1
            fi

            sleep 5
        done

        playground container exec --container "${resolved_container}" --command "java -version"
        continue
    fi

    set +e
    # for 8.x install yum
    playground container exec --container "${resolved_container}" --root --command "microdnf -y install yum" > /dev/null 2>&1
    set -e
    log "🤎 Installing Azul JDK ${version} on container ${container}"
    playground container exec --container "${resolved_container}" --root --command "yum install -y https://cdn.azul.com/zulu/bin/zulu-repo-1.0.0-1.noarch.rpm ; yum -y install zulu${version}-jdk"
    if [ $? -eq 0 ]
    then
        java_path=$(playground --output-level ERROR container exec --container "${resolved_container}" --root --command "update-alternatives --display java | grep \"java-${version}-zulu-openjdk\" | grep \"priority\" | head -1 | cut -d \" \" -f 1")
        if [ -n "$java_path" ]
        then
            playground container exec --container "${resolved_container}" --root --command "update-alternatives --set java \"$java_path\""
        else
            logerror "could not find java ${version} in alternatives list"
        fi
        if [[ "$environment" == "cfk" ]]
        then
            logwarn "CFK mode: skipping pod restart because in-pod package changes are not persistent across restart"
            logwarn "Use a custom image to persist JDK ${version} after pod recreation"
            playground container exec --container "${resolved_container}" --command "java -version"
        else
            playground container restart --container "${resolved_container}"

            sleep 5

            playground container exec --container "${resolved_container}" --command "java -version"
        fi
    else
        logerror "❌ failed to install Azul JDK ${version}"
    fi
done