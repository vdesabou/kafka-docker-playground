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

        connect_cr_json=$(kubectl -n confluent get connect connect -o json 2>/dev/null)
        current_image=$(echo "$connect_cr_json" | jq -r '.spec.image.application // empty')
        if [[ -z "$current_image" ]]
        then
            logerror "❌ could not read current Connect image from Connect CR"
            exit 1
        fi

        local_image="playground-connect-zulu${version}:$(date '+%Y%m%d%H%M%S')"
        build_dir=$(mktemp -d -t pg-jdk-build-XXXXXXXXXX)

        connect_plugins_file=""
        connect_confluent_hub_plugins=$(echo "$connect_cr_json" | jq -r '.spec.build.onDemand.plugins.confluentHub[]? | "\(.owner)|\(.name)|\(.version)"')
        if [[ -n "$connect_confluent_hub_plugins" ]]
        then
            connect_plugins_file="$build_dir/cfk-confluent-hub-plugins.txt"
            echo "$connect_confluent_hub_plugins" > "$connect_plugins_file"
        fi

        connect_url_plugins_file=""
        connect_url_plugins_dir=""
        connect_url_plugins=$(echo "$connect_cr_json" | jq -r '.spec.build.onDemand.plugins.url[]? | "\(.name)|\(.archivePath)|\(.checksum)"')
        if [[ -n "$connect_url_plugins" ]]
        then
            connect_url_plugins_file="$build_dir/cfk-url-plugins.txt"
            connect_url_plugins_dir="$build_dir/cfk-url-plugins"
            mkdir -p "$connect_url_plugins_dir"
            : > "$connect_url_plugins_file"

            url_index=0
            while IFS='|' read -r url_name url_archive_path url_checksum
            do
                if [[ -z "$url_name" || -z "$url_archive_path" ]]
                then
                    continue
                fi

                safe_url_name=$(echo "$url_name" | sed -E 's/[^a-zA-Z0-9._-]+/_/g')
                archive_file_rel="${safe_url_name}-${url_index}.zip"
                archive_file_abs="$connect_url_plugins_dir/$archive_file_rel"
                checksum_verifiable=1
                use_confluent_hub_fallback=0

                log "🔌 Downloading URL plugin archive for $url_name"
                download_candidates=("$url_archive_path")
                if [[ "$url_archive_path" == *"host.docker.internal"* ]]
                then
                    download_candidates+=("$(echo "$url_archive_path" | sed 's#host\.docker\.internal#localhost#g')")
                    download_candidates+=("$(echo "$url_archive_path" | sed 's#host\.docker\.internal#127.0.0.1#g')")
                fi

                download_success=0
                for download_url in "${download_candidates[@]}"
                do
                    if curl -fsSL "$download_url" -o "$archive_file_abs"
                    then
                        download_success=1
                        break
                    fi
                done

                if [[ "$download_success" != "1" ]]
                then
                    logwarn "⚠️ URL download failed for $url_name, trying to package plugin from running pod $resolved_container"
                    archive_file_rel="${safe_url_name}-${url_index}.tar"
                    archive_file_abs="$connect_url_plugins_dir/$archive_file_rel"

                          if kubectl -n confluent exec "$resolved_container" -c connect -- sh -lc "plugin_source_dir=''; for d in '/usr/share/confluent-hub-components/${url_name}' '/mnt/plugins/${url_name}'; do if [ -d \"\$d\" ]; then plugin_source_dir=\"\$d\"; break; fi; done; [ -n \"\$plugin_source_dir\" ] || exit 1; plugin_parent=\"\${plugin_source_dir%/*}\"; plugin_dir=\"\${plugin_source_dir##*/}\"; tar -C \"\$plugin_parent\" -cf - \"\$plugin_dir\"" > "$archive_file_abs" 2>/dev/null \
                              || kubectl -n confluent exec "$resolved_container" -- sh -lc "plugin_source_dir=''; for d in '/usr/share/confluent-hub-components/${url_name}' '/mnt/plugins/${url_name}'; do if [ -d \"\$d\" ]; then plugin_source_dir=\"\$d\"; break; fi; done; [ -n \"\$plugin_source_dir\" ] || exit 1; plugin_parent=\"\${plugin_source_dir%/*}\"; plugin_dir=\"\${plugin_source_dir##*/}\"; tar -C \"\$plugin_parent\" -cf - \"\$plugin_dir\"" > "$archive_file_abs" 2>/dev/null
                    then
                        if [[ -s "$archive_file_abs" ]]
                        then
                            download_success=1
                            checksum_verifiable=0
                            log "🔌 Reused installed plugin $url_name from pod $resolved_container"
                        else
                            rm -f "$archive_file_abs"
                        fi
                    fi

                    if [[ "$download_success" != "1" ]]
                    then
                        hub_owner="${url_name%%-*}"
                        hub_name="${url_name#*-}"
                        if [[ -n "$hub_owner" && -n "$hub_name" && "$hub_owner" != "$url_name" ]]
                        then
                            if [[ -z "$connect_plugins_file" ]]
                            then
                                connect_plugins_file="$build_dir/cfk-confluent-hub-plugins.txt"
                                : > "$connect_plugins_file"
                            fi
                            if ! grep -Fqx "${hub_owner}|${hub_name}|latest" "$connect_plugins_file" 2>/dev/null
                            then
                                echo "${hub_owner}|${hub_name}|latest" >> "$connect_plugins_file"
                            fi
                            use_confluent_hub_fallback=1
                            download_success=1
                            logwarn "⚠️ Falling back to Confluent Hub install for $url_name as ${hub_owner}/${hub_name}:latest"
                        fi
                    fi

                    if [[ "$download_success" != "1" ]]
                    then
                        logerror "❌ failed to download URL plugin archive for $url_name from $url_archive_path"
                        logerror "❌ and failed to package plugin $url_name from pod $resolved_container"
                        rm -rf "$build_dir"
                        exit 1
                    fi
                fi

                if [[ "$use_confluent_hub_fallback" == "1" ]]
                then
                    url_index=$((url_index+1))
                    continue
                fi

                if [[ -n "$url_checksum" && "$checksum_verifiable" == "1" ]]
                then
                    downloaded_checksum=$(shasum -a 512 "$archive_file_abs" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
                    expected_checksum=$(echo "$url_checksum" | tr '[:upper:]' '[:lower:]')
                    if [[ "$downloaded_checksum" != "$expected_checksum" ]]
                    then
                        logerror "❌ checksum mismatch for URL plugin $url_name"
                        logerror "expected: $expected_checksum"
                        logerror "actual:   $downloaded_checksum"
                        rm -rf "$build_dir"
                        exit 1
                    fi
                fi

                echo "${url_name}|${archive_file_rel}" >> "$connect_url_plugins_file"
                url_index=$((url_index+1))
            done <<< "$connect_url_plugins"
        fi

        log "🏗️ Building persistent CFK Connect image with JDK ${version} from ${current_image}"
        cat << EOF > "$build_dir/Dockerfile"
FROM ${current_image}
USER root
$(if [[ -n "$connect_plugins_file" ]]; then echo 'COPY cfk-confluent-hub-plugins.txt /tmp/cfk-confluent-hub-plugins.txt'; fi)
$(if [[ -n "$connect_url_plugins_file" ]]; then echo 'COPY cfk-url-plugins.txt /tmp/cfk-url-plugins.txt'; fi)
$(if [[ -n "$connect_url_plugins_dir" ]]; then echo 'COPY cfk-url-plugins/ /tmp/cfk-url-plugins/'; fi)
RUN if command -v microdnf >/dev/null 2>&1; then microdnf -y install yum; fi \
 && yum install -y https://cdn.azul.com/zulu/bin/zulu-repo-1.0.0-1.noarch.rpm \
 && yum -y install zulu${version}-jdk unzip \
 && if [ -f /tmp/cfk-confluent-hub-plugins.txt ]; then while IFS='|' read -r owner name version_value; do [ -z "\$owner" ] && continue; confluent-hub install --no-prompt "\${owner}/\${name}:\${version_value}"; done < /tmp/cfk-confluent-hub-plugins.txt; fi \
 && if [ -f /tmp/cfk-url-plugins.txt ]; then while IFS='|' read -r plugin_name plugin_archive_file; do [ -z "\$plugin_name" ] && continue; [ -z "\$plugin_archive_file" ] && continue; plugin_archive_path="/tmp/cfk-url-plugins/\${plugin_archive_file}"; plugin_unpack_dir="/tmp/cfk-url-plugin-unpack-\${plugin_name}"; rm -rf "\$plugin_unpack_dir"; mkdir -p "\$plugin_unpack_dir"; case "\$plugin_archive_path" in *.zip) unzip -q "\$plugin_archive_path" -d "\$plugin_unpack_dir" ;; *.tar) tar -xf "\$plugin_archive_path" -C "\$plugin_unpack_dir" ;; *) unzip -q "\$plugin_archive_path" -d "\$plugin_unpack_dir" ;; esac; plugin_src_dir="\$plugin_unpack_dir"; if [ "\$(find "\$plugin_unpack_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')" = "1" ] && [ -z "\$(find "\$plugin_unpack_dir" -mindepth 1 -maxdepth 1 -type f -print -quit)" ]; then plugin_src_dir="\$(find "\$plugin_unpack_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"; fi; mkdir -p "/usr/share/confluent-hub-components/\${plugin_name}"; cp -R "\$plugin_src_dir"/. "/usr/share/confluent-hub-components/\${plugin_name}/"; done < /tmp/cfk-url-plugins.txt; fi \
 && chown -R 1000:1000 /usr/share/confluent-hub-components || true \
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