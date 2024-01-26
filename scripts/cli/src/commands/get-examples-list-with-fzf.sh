without_repro="${args[--without-repro]}"
sink_only="${args[--sink-only]}"
ccloud_only="${args[--ccloud-only]}"
cur="${args[cur]}"

if [[ -n "$without_repro" ]] && [[ -n "$sink_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only ]
    then
        generate_get_examples_list_with_fzf_without_repro_sink_only
    fi
    get_examples_list_with_fzf_without_repro_sink_only "$cur"
    return
fi

if [[ -n "$without_repro" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro ]
    then
        generate_get_examples_list_with_fzf_without_repro
    fi
    get_examples_list_with_fzf_without_repro "$cur"
    return
fi

if [[ -n "$ccloud_only" ]]
then
    if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only ]
    then
        generate_get_examples_list_with_fzf_ccloud_only
    fi
    get_examples_list_with_fzf_ccloud_only "$cur"
    return
fi

if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf ]
then
    generate_get_examples_list_with_fzf
fi
get_examples_list_with_fzf "$cur"