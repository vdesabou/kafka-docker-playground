name="${args[name]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"

secret_delete_value "$name" "$profile"
