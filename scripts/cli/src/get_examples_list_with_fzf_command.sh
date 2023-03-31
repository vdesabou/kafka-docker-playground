without_repro="${args[--without-repro]}"

if [[ -n "$without_repro" ]]
then
    get_examples_list_with_fzf "true"
else
    get_examples_list_with_fzf
fi