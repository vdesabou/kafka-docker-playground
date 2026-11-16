#!/bin/bash
# Runs once when a GitHub Codespace (or a VS Code dev container, or a Codespaces prebuild) is created from .devcontainer/devcontainer.json:
# installs fzf, python3, podman and the Confluent CLI, and puts playground and its completion in the PATH, like https://kafka-docker-playground.io/install.sh
# does on a laptop. The block uses the same markers as install.sh, so 'install.sh --uninstall' removes it too.
set -e

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# fzf: the menus of playground run and others
# python3, pip and venv: playground analyze, schema, connector-plugin, connector diagnose...
# podman 5 (+ netavark, aardvark-dns, crun, like scripts/ci-setup-podman.sh): 'playground switch-podman' runs the
# examples on it instead of Docker. The rootful socket is started by .devcontainer/start-podman.sh (no systemd here)
packages=""
for pair in fzf:fzf python3:python3 pip3:python3-pip podman:podman
do
  command -v "${pair%%:*}" > /dev/null 2>&1 || packages="$packages ${pair#*:}"
done
python3 -c 'import venv, ensurepip' > /dev/null 2>&1 || packages="$packages python3-venv"
case "$packages" in
  *podman*) packages="$packages netavark aardvark-dns crun" ;;
esac
if [ -n "$packages" ]
then
  echo "📦 installing$packages"
  sudo apt-get update -qq
  # shellcheck disable=SC2086
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $packages
fi

if command -v podman > /dev/null 2>&1
then
  # same settings as scripts/ci-setup-podman.sh: netavark so that compose services resolve each other by name,
  # crun rather than the runc of docker's containerd.io, and short image names (postgres:14) resolved on docker.io
  sudo mkdir -p /etc/containers/containers.conf.d /etc/containers/registries.conf.d
  printf '[network]\nnetwork_backend = "netavark"\n\n[engine]\nruntime = "crun"\n' | sudo tee /etc/containers/containers.conf.d/99-playground.conf > /dev/null
  printf 'unqualified-search-registries = ["docker.io"]\nshort-name-mode = "permissive"\n' | sudo tee /etc/containers/registries.conf.d/99-playground.conf > /dev/null
fi

# the Confluent CLI, used by the Confluent Cloud examples (ccloud/). Best effort: a failure never breaks the codespace
if ! command -v confluent > /dev/null 2>&1
then
  echo "📦 installing the Confluent CLI"
  # the installer runs "curl -n", which fails with "(26) .netrc error: no such file" on recent curl without ~/.netrc
  touch "$HOME/.netrc"
  for i in 1 2 3
  do
    curl -fsSL --http1.1 https://cnfl.io/cli | sudo sh -s -- -b /usr/local/bin && break
    echo "⚠️ Confluent CLI install failed (attempt $i/3), retrying in 10s..."
    sleep 10
  done
  command -v confluent > /dev/null 2>&1 || echo "⚠️ the Confluent CLI is not installed: curl -sL --http1.1 https://cnfl.io/cli | sudo sh -s -- -b /usr/local/bin"
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
