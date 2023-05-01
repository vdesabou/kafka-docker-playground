without_repro="${args[--without-repro]}"
sink_only="${args[--sink-only]}"
ccloud_only="${args[--ccloud-only]}"
cur="${args[cur]}"

if [[ -n "$without_repro" ]] && [[ -n "$sink_only" ]]
then
    get_examples_list_with_fzf_without_repro_sink_only "$cur"
    return
fi

if [[ -n "$without_repro" ]]
then
    get_examples_list_with_fzf_without_repro "$cur"
    return
fi

if [[ -n "$ccloud_only" ]]
then
    get_examples_list_with_fzf_ccloud_only "$cur"
    return
fi

get_examples_list_with_fzf "$cur"