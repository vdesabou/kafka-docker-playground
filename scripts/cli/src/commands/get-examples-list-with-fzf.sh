without_repro="${args[--without-repro]}"
sink_only="${args[--sink-only]}"
ccloud_only="${args[--ccloud-only]}"

connector_only="${args[--connector-only]}"
repro_only="${args[--repro-only]}"
environment_only="${args[--environment-only]}"
fully_managed_connector_only="${args[--fully-managed-connector-only]}"
ksql_only="${args[--ksql-only]}"
schema_registry_only="${args[--schema-registry-only]}"
rest_proxy_only="${args[--rest-proxy-only]}"
academy_only="${args[--academy-only]}"
other_playgrounds_only="${args[--other-playgrounds-only]}"

cur="${args[cur]}"

if [[ -n "$without_repro" ]] && [[ -n "$sink_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only ]
    then
        generate_get_examples_list_with_fzf_without_repro_sink_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only"
    return
fi

if [[ -n "$without_repro" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro ]
    then
        generate_get_examples_list_with_fzf_without_repro
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_without_repro"
    return
fi

if [[ -n "$ccloud_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only ]
    then
        generate_get_examples_list_with_fzf_ccloud_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only"
    return
fi

if [[ -n "$connector_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_connector_only ]
    then
        generate_get_examples_list_with_fzf_connector_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_connector_only"
    return
fi

if [[ -n "$repro_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_repro_only ]
    then
        generate_get_examples_list_with_fzf_repro_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_repro_only"
    return
fi

if [[ -n "$environment_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_environment_only ]
    then
        generate_get_examples_list_with_fzf_environment_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_environment_only"
    return
fi

if [[ -n "$fully_managed_connector_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_fully_managed_connector_only ]
    then
        generate_get_examples_list_with_fzf_fully_managed_connector_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_fully_managed_connector_only"
    return
fi

if [[ -n "$ksql_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_ksql_only ]
    then
        generate_get_examples_list_with_fzf_ksql_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_ksql_only"
    return
fi

if [[ -n "$schema_registry_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_schema_registry_only ]
    then
        generate_get_examples_list_with_fzf_schema_registry_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_schema_registry_only"
    return
fi

if [[ -n "$rest_proxy_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_rest_proxy_only ]
    then
        generate_get_examples_list_with_fzf_rest_proxy_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_rest_proxy_only"
    return
fi

if [[ -n "$academy_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_academy_only ]
    then
        generate_get_examples_list_with_fzf_academy_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_academy_only"
    return
fi

if [[ -n "$other_playgrounds_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_other_playgrounds_only ]
    then
        generate_get_examples_list_with_fzf_other_playgrounds_only
    fi
    get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_other_playgrounds_only"
    return
fi

if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_all ]
then
    generate_get_examples_list_with_fzf
fi
get_examples_list_with_fzf "$cur" "$root_folder/scripts/cli/get_examples_list_with_fzf_all"