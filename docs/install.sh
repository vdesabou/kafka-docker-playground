#!/usr/bin/env bash
# kafka-docker-playground installer
#
#   curl -fsSL https://kafka-docker-playground.io/install.sh | bash
#   curl -fsSL https://kafka-docker-playground.io/install.sh | bash -s -- --dry-run
#
# What it does, asking before each change:
#   1. checks git, bash 4+, fzf, docker + compose v2 (or podman), free disk space, and changes nothing
#   2. installs what is missing with brew (macOS) or the package manager (Linux): bash, fzf, git, and the
#      Confluent CLI (used by the Confluent Cloud examples). It never installs Docker or Podman: it gives you the link instead.
#   3. clones the repository (--depth 1), or updates an existing clone
#   4. adds ONE block, between markers, to ~/.zshrc / ~/.bashrc / ~/.bash_profile, with a backup of the file:
#        # >>> kafka-docker-playground >>>
#        export PATH="<dir>/scripts/cli:$PATH"
#        source "<dir>/scripts/cli/completions.zsh"
#        # <<< kafka-docker-playground <<<
#   5. runs 'playground doctor'
#
# Options:
#   --dir <path>   where to clone (default: the clone 'playground' already comes from, else ~/kafka-docker-playground)
#   --branch <b>   branch to clone (default: master)
#   --yes, -y      answer yes to every question (no prompt, for scripts and CI)
#   --dry-run      show what would be done, change nothing
#   --no-rc        do not touch any shell startup file
#   --no-confluent-cli  do not install the Confluent CLI (only needed by the Confluent Cloud examples)
#   --uninstall    remove the block from the shell startup files, then offer to delete the clone
#   --help, -h     this help
#
# Works with the bash 3.2 of macOS: everything is in functions and runs from the last line only, so a
# download cut halfway runs nothing.

set -u

KDP_REPO_URL="https://github.com/vdesabou/kafka-docker-playground.git"
KDP_DOCS_URL="https://kafka-docker-playground.io"
MARKER_BEGIN="# >>> kafka-docker-playground >>>"
MARKER_END="# <<< kafka-docker-playground <<<"

opt_dir=""
opt_branch="master"
opt_yes=0
opt_dry_run=0
opt_no_rc=0
opt_no_confluent_cli=0
opt_uninstall=0

nb_errors=0
nb_warnings=0

if [ -t 1 ]
then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[0;31m'; C_YELLOW=$'\033[0;33m'; C_GREEN=$'\033[0;32m'; C_BLUE=$'\033[0;34m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_YELLOW=""; C_GREEN=""; C_BLUE=""
fi

log()      { printf '%s\n' "${C_BLUE}ℹ️  $*${C_RESET}"; }
log_ok()   { printf '%s\n' "${C_GREEN}✅ $*${C_RESET}"; }
logwarn()  { printf '%s\n' "${C_YELLOW}⚠️  $*${C_RESET}"; nb_warnings=$((nb_warnings+1)); }
logerror() { printf '%s\n' "${C_RED}❌ $*${C_RESET}" >&2; nb_errors=$((nb_errors+1)); }
title()    { printf '\n%s\n' "${C_BOLD}$*${C_RESET}"; }
die()      { logerror "$*"; exit 1; }

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'
  if [ ! -f "${BASH_SOURCE[0]:-}" ]
  then
    echo "usage: curl -fsSL ${KDP_DOCS_URL}/install.sh | bash -s -- [--dir <path>] [--branch <b>] [--yes] [--dry-run] [--no-rc] [--uninstall]"
  fi
}

# run a command, or only print it with --dry-run
run() {
  if [ "$opt_dry_run" = "1" ]
  then
    printf '%s\n' "   ${C_YELLOW}[dry-run] would run:${C_RESET} $*"
    return 0
  fi
  printf '%s\n' "   ${C_BOLD}\$ $*${C_RESET}"
  "$@"
}

# ask a yes/no question on the terminal (stdin is the script itself with curl | bash)
# usage: confirm "question" [default y|n]
confirm() {
  local question="$1" default="${2:-y}" answer hint
  if [ "$opt_yes" = "1" ]
  then
    return 0
  fi
  if [ "$opt_dry_run" = "1" ]
  then
    printf '%s\n' "   ${C_YELLOW}[dry-run] would ask:${C_RESET} $question (answering yes)"
    return 0
  fi
  if ! { : < /dev/tty; } 2> /dev/null
  then
    die "no terminal to ask \"$question\": run again with --yes to accept every step, or --dry-run to only look"
  fi
  if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  while true
  do
    printf '%s' "❓ $question $hint " > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    [ -z "$answer" ] && answer="$default"
    case "$answer" in
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
    esac
  done
}

parse_args() {
  while [ $# -gt 0 ]
  do
    case "$1" in
      --dir) [ $# -ge 2 ] || die "--dir needs a path"; opt_dir="$2"; shift 2 ;;
      --dir=*) opt_dir="${1#--dir=}"; shift ;;
      --branch) [ $# -ge 2 ] || die "--branch needs a branch name"; opt_branch="$2"; shift 2 ;;
      --branch=*) opt_branch="${1#--branch=}"; shift ;;
      -y|--yes) opt_yes=1; shift ;;
      --dry-run) opt_dry_run=1; shift ;;
      --no-rc) opt_no_rc=1; shift ;;
      --no-confluent-cli) opt_no_confluent_cli=1; shift ;;
      --uninstall) opt_uninstall=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
  done
  # a literal ~ given in quotes (--dir "~/kdp")
  # shellcheck disable=SC2088
  case "$opt_dir" in
    "~") opt_dir="$HOME" ;;
    "~/"*) opt_dir="$HOME/${opt_dir#\~/}" ;;
  esac
}

# ---------------------------------------------------------------------------------------------------------------------
# environment detection
# ---------------------------------------------------------------------------------------------------------------------

os=""; arch=""; brew_bin=""; pkg_manager=""; bash4=""; user_shell=""

detect_os() {
  arch="$(uname -m)"
  case "$(uname -s)" in
    Darwin) os="macos" ;;
    Linux)
      os="linux"
      if grep -qi microsoft /proc/version 2> /dev/null; then os="wsl"; fi
      ;;
    *) die "$(uname -s) is not supported: the playground runs on macOS, Linux and Windows through WSL 2" ;;
  esac

  if [ "$os" = "macos" ]
  then
    if command -v brew > /dev/null 2>&1; then brew_bin="$(command -v brew)"
    elif [ -x /opt/homebrew/bin/brew ]; then brew_bin=/opt/homebrew/bin/brew
    elif [ -x /usr/local/bin/brew ]; then brew_bin=/usr/local/bin/brew
    fi
  else
    for pm in apt-get dnf yum zypper pacman apk
    do
      if command -v "$pm" > /dev/null 2>&1; then pkg_manager="$pm"; break; fi
    done
  fi

  user_shell="$(basename "${SHELL:-bash}")"
}

bash_major() {
  "$1" -c 'echo "${BASH_VERSINFO[0]}"' 2> /dev/null || echo 0
}

# first bash 4+ found: the one of the PATH first ('playground' starts with #!/usr/bin/env bash), then brew's
find_bash4() {
  bash4=""
  local candidate
  for candidate in "$(command -v bash 2> /dev/null)" /opt/homebrew/bin/bash /usr/local/bin/bash /home/linuxbrew/.linuxbrew/bin/bash
  do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && [ "$(bash_major "$candidate")" -ge 4 ]
    then
      bash4="$candidate"
      return 0
    fi
  done
  return 1
}

path_bash_is_4() {
  local b
  b="$(command -v bash 2> /dev/null)"
  [ -n "$b" ] && [ "$(bash_major "$b")" -ge 4 ]
}

# the repository folder an existing 'playground' in the PATH belongs to
existing_install_dir() {
  local p dir
  p="$(command -v playground 2> /dev/null)" || return 1
  dir="$(cd "$(dirname "$p")/../.." 2> /dev/null && pwd)" || return 1
  [ -f "$dir/scripts/utils.sh" ] && echo "$dir"
}

is_kdp_clone() {
  [ -d "$1/.git" ] && [ -f "$1/scripts/cli/playground" ] && [ -f "$1/scripts/utils.sh" ]
}

rc_files_for_shell() {
  case "$user_shell" in
    zsh) echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash)
      if [ "$os" = "macos" ]; then echo "$HOME/.bash_profile"; else echo "$HOME/.bashrc"; fi
      ;;
    *) echo "" ;;
  esac
}

# ---------------------------------------------------------------------------------------------------------------------
# 1. checks (change nothing)
# ---------------------------------------------------------------------------------------------------------------------

missing_packages=""
confluent_missing=0
# set when the Confluent CLI is in ~/.local/bin and that folder is not in the PATH: the shell block adds it
confluent_bin_dir=""

path_has_dir() {
  case ":$PATH:" in *":$1:"*) return 0 ;; *) return 1 ;; esac
}

check_confluent_cli() {
  local version
  if command -v confluent > /dev/null 2>&1
  then
    version="$(confluent version 2> /dev/null | awk '/^Version/ {print $2}')"
    log_ok "Confluent CLI ${version}"
  elif [ -x "$HOME/.local/bin/confluent" ]
  then
    version="$("$HOME/.local/bin/confluent" version 2> /dev/null | awk '/^Version/ {print $2}')"
    log_ok "Confluent CLI ${version} in $HOME/.local/bin (the PATH block will add that folder)"
    path_has_dir "$HOME/.local/bin" || confluent_bin_dir="$HOME/.local/bin"
  elif [ "$opt_no_confluent_cli" = "1" ]
  then
    log "Confluent CLI not installed (--no-confluent-cli)"
  else
    log "Confluent CLI not installed (used by the Confluent Cloud examples)"
    confluent_missing=1
  fi
}

check_prerequisites() {
  title "🔎 1/5 Checking your machine (nothing is changed)"
  log "system: $os ($arch), shell: $user_shell"

  if command -v git > /dev/null 2>&1
  then
    log_ok "git $(git --version | awk '{print $3}')"
  else
    logwarn "git is missing"
    missing_packages="$missing_packages git"
  fi

  if find_bash4
  then
    if path_bash_is_4
    then
      log_ok "bash $("$bash4" -c 'echo $BASH_VERSION')"
    else
      log_ok "bash $("$bash4" -c 'echo $BASH_VERSION') in $bash4 (the default bash is older: the PATH block will put it first)"
    fi
  else
    logwarn "bash 4 or later is missing (macOS ships bash 3.2, the playground needs 4+)"
    missing_packages="$missing_packages bash"
  fi

  if command -v fzf > /dev/null 2>&1
  then
    log_ok "fzf $(fzf --version 2> /dev/null | awk '{print $1}')"
  else
    logwarn "fzf is missing (used by the interactive menus of playground)"
    missing_packages="$missing_packages fzf"
  fi

  check_confluent_cli

  if ! command -v docker > /dev/null 2>&1
  then
    logwarn "the 'docker' CLI is missing: install Docker Desktop (https://docs.docker.com/get-docker/) or Podman 5+ with podman-docker (${KDP_DOCS_URL}/#/how-to-use?id=%f0%9f%a6%ad-using-podman-instead-of-docker)"
  else
    if docker compose version > /dev/null 2>&1
    then
      log_ok "docker compose $(docker compose version --short 2> /dev/null)"
    else
      logwarn "the 'docker compose' v2 plugin is missing: https://docs.docker.com/compose/install/"
    fi
    if docker info > /dev/null 2>&1
    then
      log_ok "container engine is running"
    else
      logwarn "the container engine is not running (start Docker Desktop or the podman machine), or you cannot reach it"
    fi
  fi

  local free_kb free_gb
  free_kb="$(df -Pk "$HOME" 2> /dev/null | awk 'NR==2 {print $4}')"
  if [ -n "$free_kb" ]
  then
    free_gb=$((free_kb / 1024 / 1024))
    if [ "$free_gb" -lt 20 ]
    then
      logwarn "only ${free_gb}GB free in $HOME: Confluent Platform images take 10 to 30GB"
    else
      log_ok "${free_gb}GB free disk space"
    fi
  fi
}

# ---------------------------------------------------------------------------------------------------------------------
# 2. missing tools
# ---------------------------------------------------------------------------------------------------------------------

# the Confluent CLI: brew on macOS, else the official installer into ~/.local/bin (no sudo)
install_confluent_cli() {
  [ "$confluent_missing" = "1" ] || return 0
  if [ "$os" = "macos" ] && [ -n "$brew_bin" ]
  then
    if confirm "install the Confluent CLI, used by the Confluent Cloud examples ($brew_bin install confluentinc/tap/cli)?"
    then
      run "$brew_bin" install confluentinc/tap/cli || { logwarn "brew install of the Confluent CLI failed: https://docs.confluent.io/confluent-cli/current/install.html"; return 0; }
    else
      log "skipped: install it later from https://docs.confluent.io/confluent-cli/current/install.html if you use Confluent Cloud"
    fi
    return 0
  fi
  if ! command -v curl > /dev/null 2>&1
  then
    logwarn "curl is missing: install the Confluent CLI yourself from https://docs.confluent.io/confluent-cli/current/install.html"
    return 0
  fi
  if confirm "install the Confluent CLI, used by the Confluent Cloud examples, into $HOME/.local/bin (curl -sL --http1.1 https://cnfl.io/cli | sh)?"
  then
    run mkdir -p "$HOME/.local/bin"
    run sh -c "curl -sL --http1.1 https://cnfl.io/cli | sh -s -- -b \"$HOME/.local/bin\"" \
      || { logwarn "the Confluent CLI install failed: https://docs.confluent.io/confluent-cli/current/install.html"; return 0; }
    path_has_dir "$HOME/.local/bin" || confluent_bin_dir="$HOME/.local/bin"
  else
    log "skipped: install it later from https://docs.confluent.io/confluent-cli/current/install.html if you use Confluent Cloud"
  fi
}

sudo_cmd() {
  if [ "$(id -u)" = "0" ]; then echo ""; else echo "sudo"; fi
}

install_missing() {
  title "📦 2/5 Missing tools"
  missing_packages="$(echo "$missing_packages" | xargs)"
  if [ -z "$missing_packages" ]
  then
    log_ok "nothing to install"
    return 0
  fi

  local sudo
  sudo="$(sudo_cmd)"
  case "$os" in
    macos)
      if [ -z "$brew_bin" ]
      then
        logerror "missing: $missing_packages, and Homebrew is not installed"
        log "install Homebrew first (https://brew.sh), then run this installer again, or install them yourself"
        return 1
      fi
      if confirm "install $missing_packages with Homebrew ($brew_bin install $missing_packages)?"
      then
        run "$brew_bin" install $missing_packages || { logerror "brew install failed"; return 1; }
      else
        logwarn "skipped: install $missing_packages yourself before using playground"
        return 0
      fi
      ;;
    *)
      local cmd=""
      case "$pkg_manager" in
        apt-get) cmd="$sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing_packages" ;;
        dnf|yum) cmd="$sudo $pkg_manager install -y $missing_packages" ;;
        zypper) cmd="$sudo zypper install -y $missing_packages" ;;
        pacman) cmd="$sudo pacman -S --noconfirm $missing_packages" ;;
        apk) cmd="$sudo apk add $missing_packages" ;;
        *)
          logerror "missing: $missing_packages, and no known package manager: install them yourself"
          return 1
          ;;
      esac
      if confirm "install $missing_packages ($(echo $cmd | xargs))?"
      then
        if [ "$pkg_manager" = "apt-get" ]
        then
          run $sudo apt-get update -qq || true
        fi
        run $cmd || { logerror "package install failed"; return 1; }
      else
        logwarn "skipped: install $missing_packages yourself before using playground"
        return 0
      fi
      ;;
  esac

  [ "$opt_dry_run" = "1" ] && return 0
  hash -r 2> /dev/null || true
  find_bash4 > /dev/null || logwarn "bash 4+ still not found"
  command -v git > /dev/null 2>&1 || logerror "git still not found"
  command -v fzf > /dev/null 2>&1 || logwarn "fzf still not found"
}

# ---------------------------------------------------------------------------------------------------------------------
# 3. clone or update
# ---------------------------------------------------------------------------------------------------------------------

install_dir=""

choose_dir() {
  local existing
  if [ -n "$opt_dir" ]
  then
    install_dir="$opt_dir"
  elif existing="$(existing_install_dir)"
  then
    install_dir="$existing"
    log "playground is already installed from $install_dir: using it"
  else
    install_dir="$HOME/kafka-docker-playground"
  fi
}

clone_or_update() {
  title "🔽 3/5 Repository in $install_dir"
  if is_kdp_clone "$install_dir"
  then
    log_ok "already cloned"
    if [ -n "$(git -C "$install_dir" status --porcelain --untracked-files=no 2> /dev/null | grep -v ' reproduction-models$')" ]
    then
      logwarn "it has local changes: not updating it (run 'playground update' yourself when ready)"
      return 0
    fi
    if confirm "update it to the latest version (git pull --ff-only)?"
    then
      run git -C "$install_dir" pull --ff-only || logwarn "could not update it: run 'git -C $install_dir pull' yourself"
    fi
    return 0
  fi

  if [ -e "$install_dir" ] && [ -n "$(ls -A "$install_dir" 2> /dev/null)" ]
  then
    die "$install_dir exists and is not a kafka-docker-playground clone: pick another folder with --dir <path>"
  fi
  if ! command -v git > /dev/null 2>&1 && [ "$opt_dry_run" = "0" ]
  then
    die "git is needed to clone the repository"
  fi
  if confirm "clone $KDP_REPO_URL (branch $opt_branch, latest version only) into $install_dir?"
  then
    run git clone --depth 1 --branch "$opt_branch" "$KDP_REPO_URL" "$install_dir" || die "git clone failed"
  else
    die "nothing more to do without the repository"
  fi
}

# ---------------------------------------------------------------------------------------------------------------------
# 4. shell startup file
# ---------------------------------------------------------------------------------------------------------------------

# prints the content of the block for a shell (zsh|bash)
rc_block() {
  local shell_name="$1"
  echo "$MARKER_BEGIN"
  echo "# added by ${KDP_DOCS_URL}/install.sh, remove with: curl -fsSL ${KDP_DOCS_URL}/install.sh | bash -s -- --uninstall"
  if ! path_bash_is_4 && [ -n "$bash4" ]
  then
    echo "export PATH=\"$(dirname "$bash4"):\$PATH\"   # bash 4+, needed by playground"
  fi
  if [ -n "$confluent_bin_dir" ]
  then
    echo "export PATH=\"$confluent_bin_dir:\$PATH\"   # Confluent CLI"
  fi
  echo "export PATH=\"$install_dir/scripts/cli:\$PATH\""
  echo "source \"$install_dir/scripts/cli/completions.$shell_name\""
  echo "$MARKER_END"
}

# prints the file without the block (and without the blank line just before it)
strip_block() {
  awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
    $0 == b { skip = 1; if (held) { held = 0 } ; next }
    $0 == e { skip = 0; next }
    skip { next }
    { if (held) print ""; held = 0 }
    /^$/ { held = 1; next }
    { print }
    END { if (held) print "" }
  ' "$1"
}

# writes new content into a file in place (keeps a symlinked dotfile a symlink)
write_in_place() {
  local file="$1" content_file="$2"
  cat "$content_file" > "$file"
}

setup_rc() {
  title "🦶 4/5 Shell setup (PATH and completion)"
  if [ "$opt_no_rc" = "1" ]
  then
    log "--no-rc: not touching any shell startup file. Add this yourself:"
    rc_block bash | sed 's/^/   /'
    return 0
  fi

  local rc shell_name
  rc="$(rc_files_for_shell)"
  case "$user_shell" in zsh) shell_name=zsh ;; *) shell_name=bash ;; esac
  if [ -z "$rc" ]
  then
    logwarn "your shell is $user_shell: add the PATH yourself, for example: $install_dir/scripts/cli"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  if [ -f "$rc" ]
  then
    strip_block "$rc" > "$tmp"
    if grep -qF "kafka-docker-playground/scripts/cli" "$tmp" 2> /dev/null || grep -qF "$install_dir/scripts/cli" "$tmp" 2> /dev/null
    then
      log_ok "$rc already sets up playground outside the installer block: leaving it as it is"
      rm -f "$tmp"
      return 0
    fi
  fi
  [ -s "$tmp" ] && echo "" >> "$tmp"
  rc_block "$shell_name" >> "$tmp"

  if [ -f "$rc" ] && cmp -s "$rc" "$tmp"
  then
    log_ok "$rc is already up to date"
    rm -f "$tmp"
    return 0
  fi

  log "this block goes into $rc:"
  rc_block "$shell_name" | sed 's/^/   /'
  if confirm "add it (a backup of the file is kept next to it)?"
  then
    if [ "$opt_dry_run" = "1" ]
    then
      printf '%s\n' "   ${C_YELLOW}[dry-run] would write the block into $rc${C_RESET}"
    else
      if [ -f "$rc" ]
      then
        local backup
        backup="$rc.kdp-backup-$(date +%Y%m%d-%H%M%S)"
        cp -p "$rc" "$backup" && log "backup: $backup"
      fi
      write_in_place "$rc" "$tmp"
      log_ok "$rc updated"
    fi
  else
    logwarn "skipped: add the block above to $rc yourself"
  fi
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------------------------------------------------
# 5. doctor
# ---------------------------------------------------------------------------------------------------------------------

run_doctor() {
  title "🩺 5/5 playground doctor"
  if [ "$opt_dry_run" = "1" ]
  then
    printf '%s\n' "   ${C_YELLOW}[dry-run] would run:${C_RESET} playground doctor"
    return 0
  fi
  if [ -z "$bash4" ] || [ ! -x "$install_dir/scripts/cli/playground" ]
  then
    logwarn "skipped: bash 4+ or the repository is missing"
    return 0
  fi
  if ! command -v docker > /dev/null 2>&1
  then
    logwarn "skipped: install Docker Desktop or Podman first, then run: playground doctor"
    return 0
  fi
  if PATH="$(dirname "$bash4"):$install_dir/scripts/cli:$PATH" "$bash4" "$install_dir/scripts/cli/playground" doctor
  then
    log_ok "the container engine is ready"
  else
    logwarn "playground doctor found a problem: fix what it says above, then run it again"
  fi
}

# ---------------------------------------------------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------------------------------------------------

uninstall() {
  title "🧹 Uninstalling kafka-docker-playground"
  local rc found=0 tmp block_dir=""
  for rc in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"
  do
    [ -f "$rc" ] || continue
    grep -qF "$MARKER_BEGIN" "$rc" || continue
    found=1
    # the folder the block points to: export PATH="<dir>/scripts/cli:$PATH"
    if [ -z "$block_dir" ]
    then
      block_dir="$(awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '$0 == b { in_block = 1; next } $0 == e { in_block = 0 } in_block && /\/scripts\/cli:/ { print }' "$rc" \
        | sed -n 's|^export PATH="\(.*\)/scripts/cli:.*|\1|p' | head -1)"
    fi
    if confirm "remove the kafka-docker-playground block from $rc?"
    then
      if [ "$opt_dry_run" = "1" ]
      then
        printf '%s\n' "   ${C_YELLOW}[dry-run] would remove the block from $rc${C_RESET}"
      else
        cp -p "$rc" "$rc.kdp-backup-$(date +%Y%m%d-%H%M%S)"
        tmp="$(mktemp)"
        strip_block "$rc" > "$tmp"
        write_in_place "$rc" "$tmp"
        rm -f "$tmp"
        log_ok "removed from $rc"
      fi
    fi
  done
  [ "$found" = "0" ] && log "no installer block in your shell startup files"

  if [ -n "$opt_dir" ]
  then
    install_dir="$opt_dir"
  elif [ -n "$block_dir" ]
  then
    install_dir="$block_dir"
  else
    install_dir="$(existing_install_dir)" || install_dir="$HOME/kafka-docker-playground"
  fi
  if is_kdp_clone "$install_dir"
  then
    logwarn "$install_dir may hold your own files: playground.ini (credentials), reproduction models, local changes"
    # never deleted by --yes alone: the default answer is no
    local saved_yes="$opt_yes"
    opt_yes=0
    if [ "$opt_dry_run" = "1" ] || ! { : < /dev/tty; } 2> /dev/null
    then
      log "keeping $install_dir (delete it yourself with: rm -rf \"$install_dir\")"
    elif confirm "also delete the folder $install_dir?" n
    then
      run rm -rf "$install_dir" && log_ok "deleted $install_dir"
    else
      log "kept $install_dir"
    fi
    opt_yes="$saved_yes"
  fi
  log "the Confluent CLI, bash, fzf and git stay installed: remove them with brew or your package manager (or rm ~/.local/bin/confluent) if you no longer need them"
  log "Docker images stay on your machine: free the space with 'docker system prune -a' if you no longer need them"
  log "open a new terminal to finish"
}

# ---------------------------------------------------------------------------------------------------------------------

main() {
  parse_args "$@"
  printf '%s\n' "${C_BOLD}🐳 kafka-docker-playground installer${C_RESET}"
  [ "$opt_dry_run" = "1" ] && log "--dry-run: nothing will be changed"
  detect_os

  if [ "$opt_uninstall" = "1" ]
  then
    uninstall
    exit 0
  fi

  check_prerequisites
  install_missing || true
  install_confluent_cli
  choose_dir
  clone_or_update
  setup_rc
  run_doctor

  title "🎉 Done"
  if [ "$opt_dry_run" = "1" ]
  then
    log "dry run finished: run again without --dry-run to install"
    exit 0
  fi
  log "playground is in $install_dir"
  if [ -n "$(rc_files_for_shell)" ] && [ "$opt_no_rc" = "0" ]
  then
    log "open a new terminal (or run: source $(rc_files_for_shell)), then try:"
  else
    log "add playground to your PATH as shown above, then try:"
  fi
  echo ""
  echo "   playground find-example \"s3 sink\"     # find an example to run"
  echo "   playground run                         # pick one in the menu and run it"
  echo ""
  log "how to use: ${KDP_DOCS_URL}/#/how-to-use"
  if [ "$nb_warnings" -gt 0 ] || [ "$nb_errors" -gt 0 ]
  then
    logwarn "$nb_warnings warning(s), $nb_errors error(s) above: fix them before your first run"
  fi
}

main "$@"
