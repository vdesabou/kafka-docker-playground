name="${args[name]}"
value="${args[--value]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"

force=""
if [[ -n "${args[--secret]}" ]]
then
    force="secret"
elif [[ -n "${args[--plain]}" ]]
then
    force="plain"
fi

if [ "$force" == "secret" ] || { [ -z "$force" ] && is_secret_env_var_name "$name"; }
then
    secret_backend_ready || exit 1
fi

if [[ ! -n "$value" ]]
then
    value=$(read_secret_value_interactively "$name") || exit 1
fi

secret_store_value "$name" "$value" "$profile" "$force"
