#!/bin/bash
# Runs once when a GitHub Codespace (or a VS Code dev container) is created from .devcontainer/devcontainer.json:
# installs fzf and puts playground and its completion in the PATH, like https://kafka-docker-playground.io/install.sh
# does on a laptop. The block uses the same markers as install.sh, so 'install.sh --uninstall' removes it too.
set -e

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v fzf > /dev/null 2>&1
then
  echo "📦 installing fzf"
  sudo apt-get update -qq
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fzf
fi

for rc in "$HOME/.bashrc" "$HOME/.zshrc"
do
  case "$rc" in
    *zshrc) shell_name=zsh ;;
    *) shell_name=bash ;;
  esac
  [ -f "$rc" ] || continue
  if grep -qF ">>> kafka-docker-playground >>>" "$rc"
  then
    continue
  fi
  cat >> "$rc" << BLOCK

# >>> kafka-docker-playground >>>
export PATH="$repo_dir/scripts/cli:\$PATH"
source "$repo_dir/scripts/cli/completions.$shell_name"
# <<< kafka-docker-playground <<<
BLOCK
  echo "✅ $rc: playground added to the PATH"
done

echo ""
echo "🐳 kafka-docker-playground is ready: open a new terminal, then try:"
echo ""
echo "   playground find-example \"s3 sink\"     # find an example to run"
echo "   playground run                         # pick one in the menu and run it"
echo ""
