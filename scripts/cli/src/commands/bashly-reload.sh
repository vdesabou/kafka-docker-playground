log "💫 generating playground CLI using Bashly (https://bashly.dev/)"
set +e
docker pull dannyben/bashly > /dev/null 2>&1
set -e

# -it only works when stdin is a terminal (not from scripts or AI agents)
maybe_tty=""
if [ -t 0 ]
then
	maybe_tty="-it"
fi

cd "$root_folder/scripts/cli"

# examples and footers are printed with printf "..." in --help, so an unescaped $VAR, ${...} or $(...) is expanded (or run)
# example lines starting with playground must call their command (or one of its aliases)
# x_example_outputs (rendered in the docs only, see templates/markdown) must start with the name of their command
bashly_yml_errors=$(yq -o=json src/bashly.yml | jq -r '
def names: [.name] + ((.alias // []) | if type == "string" then [.] else . end);
def commands(p; n): (.commands // [])[] | (p + [.name]) as $q | (n + [names]) as $m | ({path: ($q | join(" ")), names: $m, examples: ((.examples // []) | if type == "string" then [.] else . end), footer, outputs: (.x_example_outputs // [])}), commands($q; $m);
commands(["playground"]; [["playground"]])
| .path as $path | .names as $names
| ((.examples[], (.footer // empty)) | split("\n")[] | select(test("(^|[^\\\\])\\$[A-Za-z_{(]")) | "\($path): unescaped $ in example or footer, use \\$: \(.)"),
  (.examples[] | split("\n")[] | sub("^ +"; "") | select(startswith("playground ") or . == "playground") | (split(" ") | map(select(length > 0))) as $words | select([range($names | length) as $i | $names[$i] | index($words[$i]) == null] | any) | "\($path): example does not call \"\($path)\": \(.)"),
  (.outputs[] | select((.command // "" | startswith($path) | not) or ((.output // "") == "")) | "\($path): x_example_outputs entry needs an output and a command starting with \"\($path)\": \(.command)")')
if [ -n "$bashly_yml_errors" ]
then
	logerror "❌ src/bashly.yml has errors:"
	echo "$bashly_yml_errors"
	exit 1
fi

docker run --rm $maybe_tty --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly generate | grep -v "skipped"
# Since bashly 2.0, completions are answered at runtime by `playground __complete <words>`.
# The adapters below only forward to it, they only need to be regenerated when bashly is upgraded.
"$BASH" -c 'source ./playground && send_completions bash' > /tmp/playground_completions.bash
"$BASH" -c 'source ./playground && send_completions zsh' > /tmp/playground_completions.zsh
# Add shell checks (zsh sourcing the bash adapter, bash < 4, compinit not loaded), see src/completions/
cat "$root_folder/scripts/cli/src/completions/bash-header.sh" /tmp/playground_completions.bash > "$root_folder/scripts/cli/completions.bash"
# keep "#compdef playground" as first line of the zsh adapter
{ head -1 /tmp/playground_completions.zsh; cat "$root_folder/scripts/cli/src/completions/zsh-header.sh"; tail -n +2 /tmp/playground_completions.zsh; } > "$root_folder/scripts/cli/completions.zsh"
rm -f /tmp/playground_completions.bash /tmp/playground_completions.zsh
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

docker run --rm $maybe_tty --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly render templates/shell-script-command-completion .
yq -o=json playground.yaml > playground.json
cd - > /dev/null

log "✅ all done !"

# this script was regenerated while it is running: exit now, otherwise bash goes on reading it
# at the old byte offset of the new file and fails with "syntax error near unexpected token"
exit 0
