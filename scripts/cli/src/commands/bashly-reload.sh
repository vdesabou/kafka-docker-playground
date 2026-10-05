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

log 🎱 "if completions are not set up yet, you can load them using:"
echo ""
echo "source $root_folder/scripts/cli/completions.bash   # bash"
echo "source $root_folder/scripts/cli/completions.zsh    # zsh"
echo ""

docker run --rm -it --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly render templates/shell-script-command-completion .
yq -o=json playground.yaml > playground.json
cd - > /dev/null

log "✅ all done !"