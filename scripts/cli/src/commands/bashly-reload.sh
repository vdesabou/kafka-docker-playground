log "💫 generating playground CLI using Bashly (https://bashly.dev/)"
set +e
docker pull dannyben/bashly > /dev/null 2>&1
set -e

cd "$root_folder/scripts/cli"
docker run --rm -it --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly generate | grep -v "skipped"
# Since bashly 2.0, completions are answered at runtime by `playground __complete <words>`.
# The adapters below only forward to it, they only need to be regenerated when bashly is upgraded.
"$BASH" -c 'source ./playground && send_completions bash' > "$root_folder/scripts/cli/completions.bash"
"$BASH" -c 'source ./playground && send_completions zsh' > "$root_folder/scripts/cli/completions.zsh"
# Bashly 2.0.0 zsh adapter quotes the words slice without (@), so zsh joins "topic produce" into a single word
# and only top-level commands complete. Split it back into one element per word.
perl -pi -e 's/completion_words=\("\$\{words\[2,\$\(\(CURRENT - 1\)\)\]\}"\)/completion_words=("\${(\@)words[2,\$((CURRENT - 1))]}")/' "$root_folder/scripts/cli/completions.zsh"
if ! grep -q 'completion_words=("${(@)words' "$root_folder/scripts/cli/completions.zsh"
then
	logerror "❌ completions.zsh words slice fix did not apply, check the bashly zsh adapter"
	exit 1
fi

log 🎱 "if completions are not set up yet, you can load them using:"
echo ""
echo "source $root_folder/scripts/cli/completions.bash   # bash"
echo "source $root_folder/scripts/cli/completions.zsh    # zsh"
echo ""

docker run --rm -it --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly render templates/shell-script-command-completion .
yq -o=json playground.yaml > playground.json
cd - > /dev/null

log "✅ all done !"