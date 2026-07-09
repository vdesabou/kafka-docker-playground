containers="${args[--container]}"
command="${args[--command]}"
root="${args[--root]}"
shell="${args[--shell]}"

get_environment_used

declare -A cfk_root_patch_done_map
declare -A cfk_root_original_user_map
declare -A cfk_root_original_nonroot_map
declare -A cfk_root_restore_needed_map

restore_cfk_appuser_for_resource() {
	local resource_kind=$1
	local resource_name=$2
	local resolved_container=$3
	local key="$resource_kind/$resource_name"
	local original_user="${cfk_root_original_user_map[$key]}"
	local original_nonroot="${cfk_root_original_nonroot_map[$key]}"
	local patch_payload

	if [[ "${cfk_root_restore_needed_map[$key]}" != "1" ]]
	then
		return
	fi

	# If values were not explicitly set before patching, default back to appuser semantics.
	if [[ "$original_user" == "__MISSING__" || -z "$original_user" ]]
	then
		original_user="1000"
	fi
	if [[ "$original_nonroot" == "__MISSING__" || -z "$original_nonroot" ]]
	then
		original_nonroot="true"
	fi

	patch_payload=$(printf '{"spec":{"podTemplate":{"podSecurityContext":{"runAsUser":%s,"runAsNonRoot":%s}}}}' "$original_user" "$original_nonroot")
	log "↩️ Restoring $resource_kind/$resource_name to appuser-like security context (runAsUser=$original_user, runAsNonRoot=$original_nonroot)"
	patch_stderr=$(mktemp -t pg-cfk-patch-XXXXXXXXXX)
	kubectl -n confluent patch "$resource_kind" "$resource_name" --type merge -p "$patch_payload" > /dev/null 2>"$patch_stderr"
	if [ $? -ne 0 ]
	then
		logerror "❌ failed to restore $resource_kind/$resource_name security context after root execution"
		cat "$patch_stderr"
		rm -f "$patch_stderr"
		exit 1
	fi
	rm -f "$patch_stderr"

	log "⌛ Waiting for pod $resolved_container to be ready after restore patch"
	if ! kubectl -n confluent wait --for=condition=Ready "pod/$resolved_container" --timeout=300s > /dev/null 2>&1
	then
		logerror "❌ pod $resolved_container did not become ready after restore patch"
		kubectl -n confluent get pods
		exit 1
	fi

	unset 'cfk_root_restore_needed_map[$key]'
	unset 'cfk_root_patch_done_map[$key]'
}

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

ensure_cfk_root_for_container() {
	local container=$1
	local resolved_container=$2
	local resource_kind
	local resource_name
	local resource_ref

	if [[ "$environment" != "cfk" ]]
	then
		return
	fi

	local container_uid
	container_uid=$(playground --output-level ERROR container exec --container "$resolved_container" --command "id -u" 2>/dev/null || true)
	if [[ "$container_uid" == "0" ]]
	then
		return
	fi

	resource_ref=$(get_cfk_resource_for_pod "$resolved_container")
	resource_kind=${resource_ref%%:*}
	resource_name=${resource_ref#*:}

	if [[ -z "$resource_kind" || -z "$resource_name" ]]
	then
		logerror "❌ automatic root patch is not supported for pod $resolved_container"
		logerror "Could not resolve CFK component type from pod labels"
		exit 1
	fi

	if [[ "${cfk_root_patch_done_map[$resource_kind/$resource_name]}" != "1" ]]
	then
		key="$resource_kind/$resource_name"
		original_run_as_user=$(kubectl -n confluent get "$resource_kind" "$resource_name" -o jsonpath='{.spec.podTemplate.podSecurityContext.runAsUser}' 2>/dev/null)
		original_run_as_non_root=$(kubectl -n confluent get "$resource_kind" "$resource_name" -o jsonpath='{.spec.podTemplate.podSecurityContext.runAsNonRoot}' 2>/dev/null)
		if [[ -z "$original_run_as_user" ]]
		then
			original_run_as_user="__MISSING__"
		fi
		if [[ -z "$original_run_as_non_root" ]]
		then
			original_run_as_non_root="__MISSING__"
		fi
		cfk_root_original_user_map[$key]="$original_run_as_user"
		cfk_root_original_nonroot_map[$key]="$original_run_as_non_root"

		logwarn "☸️ Pod $resolved_container is running as uid ${container_uid:-unknown}; patching $resource_kind/$resource_name to run as root"
		patch_stderr=$(mktemp -t pg-cfk-patch-XXXXXXXXXX)
		kubectl -n confluent patch "$resource_kind" "$resource_name" --type merge -p '{"spec":{"podTemplate":{"podSecurityContext":{"runAsUser":0,"runAsNonRoot":false}}}}' > /dev/null 2>"$patch_stderr"
		if [ $? -ne 0 ]
		then
			logerror "❌ failed to patch $resource_kind/$resource_name for root execution"
			cat "$patch_stderr"
			rm -f "$patch_stderr"
			exit 1
		fi
		rm -f "$patch_stderr"
		cfk_root_patch_done_map[$resource_kind/$resource_name]="1"
		cfk_root_restore_needed_map[$resource_kind/$resource_name]="1"
	fi

	log "⌛ Waiting for pod $resolved_container to be ready after $resource_kind/$resource_name patch"
	if ! kubectl -n confluent wait --for=condition=Ready "pod/$resolved_container" --timeout=300s > /dev/null 2>&1
	then
		logerror "❌ pod $resolved_container did not become ready after $resource_kind/$resource_name patch"
		kubectl -n confluent get pods
		exit 1
	fi

	uid_deadline=$((SECONDS + 120))
	while true
	do
		container_uid=$(playground --output-level ERROR container exec --container "$resolved_container" --command "id -u" 2>/dev/null || true)
		if [[ "$container_uid" == "0" ]]
		then
			break
		fi

		if (( SECONDS >= uid_deadline ))
		then
			logerror "❌ pod $resolved_container is still not running as root after $resource_kind/$resource_name patch (uid: ${container_uid:-unknown})"
			exit 1
		fi

		sleep 2
	done
}

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	resolved_container=$(resolve_container_name_for_environment "$container")
	root_resource_kind=""
	root_resource_name=""
	if [[ "$environment" == "cfk" ]]
	then
		if [[ -n "$root" ]]
		then
			ensure_cfk_root_for_container "$container" "$resolved_container"
			resource_ref=$(get_cfk_resource_for_pod "$resolved_container")
			root_resource_kind=${resource_ref%%:*}
			root_resource_name=${resource_ref#*:}
			log "🪄👑 Executing command as root in pod $resolved_container with $shell"
		fi
		if [[ -z "$root" ]]
		then
			log "🪄 Executing command in pod $resolved_container with $shell"
		fi
		if [[ -t 0 ]]
		then
			kubectl -n confluent exec "$resolved_container" -- "$shell" -c "$command"
			exec_exit_code=$?
		else
			kubectl -n confluent exec -i "$resolved_container" -- "$shell" -c "$command"
			exec_exit_code=$?
		fi

		if [[ -n "$root" && -n "$root_resource_kind" && -n "$root_resource_name" ]]
		then
			restore_cfk_appuser_for_resource "$root_resource_kind" "$root_resource_name" "$resolved_container"
		fi

		if [[ $exec_exit_code -ne 0 ]]
		then
			exit $exec_exit_code
		fi
	elif [[ -n "$root" ]]
	then
	log "🪄👑 Executing command as root in container $container with $shell"
	docker exec -i --privileged --user root $resolved_container $shell -c "$command"
	else
	log "🪄 Executing command in container $container with $shell"
	docker exec -i $resolved_container $shell -c "$command"
	fi
done