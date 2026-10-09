# Prepended to completions.zsh by `playground bashly-reload`.
# compdef is only defined once compinit has run: load it if it is not there yet.
if (( ! $+functions[compdef] ))
then
  autoload -Uz compinit && compinit
fi

