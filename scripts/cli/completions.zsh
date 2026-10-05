#compdef playground

_playground_completions() {
  local completion_command="${words[1]}"
  local completion_current="${words[CURRENT]:-}"
  local completion_output
  local completion_directive
  local -a completion_words=()
  local -a completion_response=()
  local -a completion_options=()
  local -a completion_add_args=()

  if (( CURRENT > 2 )); then
    completion_words=("${words[2,$((CURRENT - 1))]}")
  fi

  completion_output="$("$completion_command" __complete "${completion_words[@]}" "$completion_current")"
  completion_response=("${(@f)completion_output}")

  completion_directive="${completion_response[-1]:-}"
  if [[ $completion_directive == :options=* ]]; then
    completion_response[-1]=()
    completion_options=("${(@s:,:)${completion_directive#:options=}}")
  fi

  local completion_option
  local completion_files=false
  local completion_directories=false
  for completion_option in "${completion_options[@]}"; do
    case "$completion_option" in
      files) completion_files=true ;;
      directories) completion_directories=true ;;
      no-space) completion_add_args=(-S "") ;;
    esac
  done

  if (( ${#completion_response[@]} > 0 )); then
    compadd "${completion_add_args[@]}" -- "${completion_response[@]}"
  fi

  if [[ $completion_files == true ]]; then
    _files "${completion_add_args[@]}"
  elif [[ $completion_directories == true ]]; then
    _files -/ "${completion_add_args[@]}"
  fi
}

compdef _playground_completions playground
