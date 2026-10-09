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

