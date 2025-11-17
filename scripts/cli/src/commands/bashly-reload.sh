log "💫 generating playground CLI using Bashly (https://bashly.dev/)"
set +e
docker pull dannyben/bashly > /dev/null 2>&1
set +e

cd "$root_folder/scripts/cli"
docker run --rm -it --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly generate
rm -f $root_folder/scripts/cli/completions.bash
docker run --rm -it --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly add completions_script --quiet

log 🎱 "if you updated bahsly.yml with new commands or modified fags, you can reload completions file using"
echo ""
echo "source $root_folder/scripts/cli/completions.bash"

docker run --rm -it --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly render templates/shell-script-command-completion .
yq -o=json playground.yaml > playground.json
cd - > /dev/null