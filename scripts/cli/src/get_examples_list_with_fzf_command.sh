without_repro="${args[--without-repro]}"
sink_only="${args[--sink-only]}"

if [[ -n "$without_repro" ]] && [[ -n "$without_repro" ]]
then
    get_examples_list_with_fzf_without_repro_sink_only
    return
fi

if [[ -n "$without_repro" ]]
then
    get_examples_list_with_fzf_without_repro
    return
fi

get_examples_list_with_fzf