# Prepended to completions.bash by `playground bashly-reload`.
# Until bashly 2.0 (#8907), zsh users sourced completions.bash through bashcompinit: it now fails in zsh
# with "_playground_completions:read:21: bad option: -a". Load the native zsh adapter instead.
if [ -n "${ZSH_VERSION:-}" ]
then
  eval '_playground_completions_zsh="${${(%):-%x}:A:h}/completions.zsh"'
  echo "⚠️ playground: completions.bash is for bash, loading completions.zsh instead. In your ~/.zshrc, replace it with: source $_playground_completions_zsh" >&2
  source "$_playground_completions_zsh"
  unset _playground_completions_zsh
  return 0
fi
# The bash adapter uses associative arrays, which need bash 4+ (macOS ships bash 3.2 in /bin/bash).
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]
then
  echo "⚠️ playground: completions need bash 4 or higher (current: $BASH_VERSION), run 'brew install bash' and use it as your shell" >&2
  return 0
fi

_playground_completions() {
  local completion_command="${COMP_WORDS[0]}"
  local completion_current="${COMP_WORDS[COMP_CWORD]:-}"
  local completion_word_count=$((COMP_CWORD - 1))
  local -a completion_words=()
  local -a completion_response=()
  local -a completion_options=()
  local -A completion_seen=()

  if [[ $completion_word_count -gt 0 ]]; then
    completion_words=("${COMP_WORDS[@]:1:completion_word_count}")
  fi

  COMPREPLY=()
  while IFS= read -r completion_line; do
    completion_response+=("$completion_line")
  done < <("$completion_command" __complete "${completion_words[@]}" "$completion_current")

  local completion_directive="${completion_response[-1]:-}"
  if [[ $completion_directive == :options=* ]]; then
    unset "completion_response[-1]"
    IFS=, read -r -a completion_options <<< "${completion_directive#:options=}"
  fi

  COMPREPLY=("${completion_response[@]}")
  local completion_candidate
  for completion_candidate in "${COMPREPLY[@]}"; do
    completion_seen["$completion_candidate"]=1
  done

  local completion_option
  local completion_files=false
  local completion_directories=false
  for completion_option in "${completion_options[@]}"; do
    case "$completion_option" in
      files) completion_files=true ;;
      directories) completion_directories=true ;;
      no-space) compopt -o nospace ;;
    esac
  done

  if [[ $completion_files == true ]]; then
    while IFS= read -r completion_candidate; do
      if [[ -z "${completion_seen[$completion_candidate]:-}" ]]; then
        COMPREPLY+=("$completion_candidate")
        completion_seen["$completion_candidate"]=1
      fi
    done < <(compgen -f -- "$completion_current")
  elif [[ $completion_directories == true ]]; then
    while IFS= read -r completion_candidate; do
      if [[ -z "${completion_seen[$completion_candidate]:-}" ]]; then
        COMPREPLY+=("$completion_candidate")
        completion_seen["$completion_candidate"]=1
      fi
    done < <(compgen -d -- "$completion_current")
  fi
}

complete -F _playground_completions playground
