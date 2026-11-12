#!/usr/bin/env bash
# kafka-docker-playground installer
#
#   curl -fsSL https://kafka-docker-playground.io/install.sh | bash
#   curl -fsSL https://kafka-docker-playground.io/install.sh | bash -s -- --dry-run
#
# What it does, asking before each change:
#   1. checks git, bash 4+, fzf, python3, docker + compose v2 (or podman), free disk space, and changes nothing
#   2. installs what is missing with brew (macOS) or the package manager (Linux): bash, fzf, git, python3, unzip, and the
#      Confluent CLI (used by the Confluent Cloud examples). On macOS without Homebrew, offers to install it first
#      (official installer from https://brew.sh), only when a tool or a container engine needs it
#   3. clones the repository (--depth 1), or updates an existing clone
#   4. when no container engine is installed at all, offers to install one: Podman or Docker Desktop on macOS,
#      Docker Engine on Linux. Never with --yes alone (pass --engine), never next to an engine already installed.
#   5. adds ONE block, between markers, to ~/.zshrc / ~/.bashrc / ~/.bash_profile, with a backup of the file:
#        # >>> kafka-docker-playground >>>
#        export PATH="<dir>/scripts/cli:$PATH"
#        source "<dir>/scripts/cli/completions.zsh"
#        # <<< kafka-docker-playground <<<
#   6. runs 'playground doctor'
#
# Options:
#   --dir <path>   where to clone (default: the clone 'playground' already comes from, else ~/kafka-docker-playground)
#   --branch <b>   branch to clone (default: master)
#   --yes, -y      answer yes to every question (no prompt, for scripts and CI)
#   --dry-run      show what would be done, change nothing
#   --no-rc        do not touch any shell startup file
#   --no-confluent-cli  do not install the Confluent CLI (only needed by the Confluent Cloud examples)
#   --engine <e>   container engine to install when none is found, without asking: podman | docker-desktop (macOS),
#                  docker (Linux), none. Without it, the installer asks (and --yes installs none)
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
opt_engine=""
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
      --engine) [ $# -ge 2 ] || die "--engine needs podman, docker-desktop, docker or none"; opt_engine="$2"; shift 2 ;;
      --engine=*) opt_engine="${1#--engine=}"; shift ;;
      --uninstall) opt_uninstall=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
  done
  case "$opt_engine" in
    ""|podman|docker-desktop|docker|none) ;;
    *) die "--engine must be podman, docker-desktop, docker or none" ;;
  esac
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
# set when Homebrew is installed but not set up in the shell (its bin folder is not in the PATH): the shell block
# then adds 'eval "$(<brew> shellenv)"', and the installer puts that folder in its own PATH
brew_shellenv_needed=0

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
    if [ -n "$brew_bin" ] && ! path_has_dir "$(dirname "$brew_bin")"
    then
      brew_shellenv_needed=1
      PATH="$(dirname "$brew_bin"):$PATH"
      export PATH
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
  title "🔎 1/6 Checking your machine (nothing is changed)"
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

  check_python3

  if ! command -v unzip > /dev/null 2>&1
  then
    logwarn "unzip is missing (used by playground connector-plugin search-jar, schema import...)"
    missing_packages="$missing_packages unzip"
  fi

  check_confluent_cli

  if ! command -v docker > /dev/null 2>&1
  then
    logwarn "the 'docker' CLI is missing: no container engine (step 4 offers to install one)"
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

# python3 3.9+, used by most support commands: playground analyze, schema, connector-plugin, connector diagnose,
# streams status, topic check-format. Only the standard library is needed.
check_python3() {
  local version
  # macOS without the Command Line Tools: /usr/bin/python3 is a stub that opens an install dialog, never run it
  if [ "$os" = "macos" ] && [ "$(command -v python3 2> /dev/null)" = "/usr/bin/python3" ] && ! xcode-select -p > /dev/null 2>&1
  then
    version=""
  elif command -v python3 > /dev/null 2>&1
  then
    version="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2> /dev/null)"
  fi
  if [ -z "${version:-}" ]
  then
    logwarn "python3 is missing (used by playground analyze, schema, connector-plugin, connector diagnose...)"
    if [ "$os" = "macos" ]; then missing_packages="$missing_packages python"; else missing_packages="$missing_packages python3"; fi
  elif python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2> /dev/null
  then
    log_ok "python3 $version"
  else
    logwarn "python3 $version is older than 3.9: playground analyze, schema and connector-plugin commands may fail, upgrade it"
  fi
}

sudo_cmd() {
  if [ "$(id -u)" = "0" ]; then echo ""; else echo "sudo"; fi
}

# macOS without Homebrew: offer to install it with the official installer (https://brew.sh), once per run, only when
# something needs it (missing tools, a container engine). Sets brew_bin and brew_shellenv_needed on success.
# usage: ensure_brew "<what needs it>"
brew_install_asked=0
ensure_brew() {
  local reason="$1" installer prefix
  [ "$os" = "macos" ] || return 1
  [ -n "$brew_bin" ] && return 0
  [ "$brew_install_asked" = "0" ] || return 1
  brew_install_asked=1
  if [ "$arch" = "arm64" ]; then prefix=/opt/homebrew; else prefix=/usr/local; fi
  if [ "$(id -u)" = "0" ]
  then
    logwarn "Homebrew is not installed, and it cannot be installed as root: run this installer as your user"
    return 1
  fi
  if ! command -v curl > /dev/null 2>&1
  then
    logwarn "Homebrew is not installed, and curl is missing to install it: https://brew.sh"
    return 1
  fi
  # the official installer needs sudo to create $prefix: only an administrator can install Homebrew there
  case "$(dseditgroup -o checkmember -m "$(id -un)" admin 2> /dev/null)" in
    "no "*)
      logwarn "Homebrew is not installed, it is needed for $reason, but $(id -un) is not an administrator of this Mac: the Homebrew installer needs one (sudo). Ask for administrator rights, or install it with an administrator account (https://brew.sh), then run this installer again"
      return 1
      ;;
  esac
  log "Homebrew is not installed, it is needed for $reason"
  log "the official Homebrew installer needs your password (sudo) and may install the Xcode Command Line Tools"
  if ! confirm "install Homebrew into $prefix (official installer from https://brew.sh)?"
  then
    log "skipped: install Homebrew yourself from https://brew.sh, then run this installer again"
    return 1
  fi
  if [ "$opt_dry_run" = "1" ]
  then
    run /usr/bin/sudo -v
    run env NONINTERACTIVE=1 /bin/bash "<Homebrew install.sh, downloaded from https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh>"
    # the next steps show the brew commands they would run
    brew_bin="$prefix/bin/brew"
    brew_shellenv_needed=1
    return 0
  fi
  # NONINTERACTIVE=1 below (this installer already asked) makes the Homebrew installer use 'sudo -n' only, which
  # never asks for a password and fails without a cached sudo timestamp: ask for the password here, once
  if ! /usr/bin/sudo -n -v 2> /dev/null
  then
    if ! { : < /dev/tty; } 2> /dev/null
    then
      logwarn "the Homebrew installer needs your password (sudo) and there is no terminal to ask it: run 'sudo -v' in this terminal, then this installer again, or install Homebrew from https://brew.sh"
      return 1
    fi
    log "enter your macOS password for the Homebrew installer (sudo)"
    if ! /usr/bin/sudo -v < /dev/tty
    then
      logwarn "sudo failed: Homebrew not installed, install it from https://brew.sh"
      return 1
    fi
  fi
  installer="$(mktemp -t homebrew-install.XXXXXX)" || { logwarn "mktemp failed: install Homebrew yourself from https://brew.sh"; return 1; }
  if ! curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"
  then
    rm -f "$installer"
    logwarn "could not download the Homebrew installer: install it yourself from https://brew.sh"
    return 1
  fi
  # NONINTERACTIVE: this installer already asked, and the sudo timestamp is cached above.
  # stdin from the terminal (with curl | bash, stdin is this script)
  if { : < /dev/tty; } 2> /dev/null
  then
    run env NONINTERACTIVE=1 /bin/bash "$installer" < /dev/tty
  else
    run env NONINTERACTIVE=1 /bin/bash "$installer" < /dev/null
  fi
  local rc=$?
  rm -f "$installer"
  if [ "$rc" != "0" ] || [ ! -x "$prefix/bin/brew" ]
  then
    logwarn "the Homebrew install failed, see its output above: https://brew.sh"
    return 1
  fi
  brew_bin="$prefix/bin/brew"
  log_ok "Homebrew installed: $brew_bin"
  if ! path_has_dir "$prefix/bin"
  then
    brew_shellenv_needed=1
    PATH="$prefix/bin:$PATH"
    export PATH
  fi
  return 0
}

install_missing() {
  title "📦 2/6 Missing tools"
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
      if ! ensure_brew "$missing_packages"
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
  command -v python3 > /dev/null 2>&1 || logwarn "python3 still not found"
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
  title "🔽 3/6 Repository in $install_dir"
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
# 4. container engine
# ---------------------------------------------------------------------------------------------------------------------

# engine_state: running | stopped (installed but not reachable) | none
engine_state="none"
engine_hint=""
# set when the user was just added to the docker group: this session is not in it yet, doctor runs through 'sg docker'
docker_group_pending=0
# set when 'playground switch-podman' ran: it already ends with 'playground doctor'
doctor_done=0

detect_engine() {
  engine_state="none"
  engine_hint=""
  # tests only: behave as on a machine without any engine (combine with --dry-run)
  if [ "${KDP_INSTALL_TEST_NO_ENGINE:-}" = "1" ] && [ "$opt_dry_run" = "1" ]
  then
    return 0
  fi
  if command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1
  then
    engine_state="running"
    return 0
  fi
  if [ "$os" = "macos" ]
  then
    if [ -d "/Applications/Docker.app" ]; then engine_state="stopped"; engine_hint="start Docker Desktop: open -a Docker"; return 0; fi
    if [ -d "/Applications/OrbStack.app" ]; then engine_state="stopped"; engine_hint="start OrbStack: open -a OrbStack"; return 0; fi
    if [ -d "/Applications/Rancher Desktop.app" ]; then engine_state="stopped"; engine_hint="start Rancher Desktop: open -a 'Rancher Desktop'"; return 0; fi
    if command -v colima > /dev/null 2>&1; then engine_state="stopped"; engine_hint="start Colima: colima start --cpu 4 --memory 12"; return 0; fi
  fi
  if command -v podman > /dev/null 2>&1
  then
    engine_state="stopped"
    if [ "$os" = "macos" ]
    then
      engine_hint="start the podman machine and point docker at it: playground switch-podman (create the machine first if needed: podman machine init --rootful --cpus 4 --memory 12288 --disk-size 100)"
    else
      engine_hint="set up the rootful podman socket: ${KDP_DOCS_URL}/#/how-to-use?id=%f0%9f%90%a7-setup-on-linux"
    fi
    return 0
  fi
  if command -v docker > /dev/null 2>&1
  then
    engine_state="stopped"
    if [ "$os" = "macos" ]
    then
      engine_hint="the docker CLI is installed but no engine answers: start Docker Desktop, OrbStack, Colima or the podman machine"
    elif [ -S /var/run/docker.sock ] && ! id -nG 2> /dev/null | grep -qw docker && [ "$(id -u)" != "0" ]
    then
      if getent group docker 2> /dev/null | cut -d: -f4 | tr ',' '\n' | grep -qx "${USER:-}"
      then
        engine_hint="you were added to the docker group: log out and back in (or run: newgrp docker)"
      else
        engine_hint="you are not in the docker group: sudo usermod -aG docker \$USER, then log out and back in"
      fi
    else
      engine_hint="start the docker daemon: sudo systemctl enable --now docker"
    fi
  fi
}

# the engines this installer can install on this machine, first one is the default
engine_choices() {
  case "$os" in
    macos) echo "podman docker-desktop" ;;
    linux) echo "docker" ;;
    wsl) if [ -d /run/systemd/system ]; then echo "docker"; fi ;;
  esac
}

engine_label() {
  case "$1" in
    podman) echo "Podman: free, installed and started for you (brew, then a podman machine)" ;;
    docker-desktop) echo "Docker Desktop: needs a paid subscription in companies with more than 250 employees or \$10M revenue" ;;
    docker) echo "Docker Engine: free, from Docker's official repository (needs sudo)" ;;
  esac
}

# asks which engine to install; prints it, or nothing to skip
choose_engine() {
  local choices="$1" i=1 c answer
  if [ "$opt_dry_run" = "1" ]
  then
    printf '%s\n' "   ${C_YELLOW}[dry-run] would ask which engine to install, choices: ${choices} (default first), or skip${C_RESET}" >&2
    echo "${choices%% *}"
    return 0
  fi
  if ! { : < /dev/tty; } 2> /dev/null
  then
    return 0
  fi
  {
    echo "No container engine found: the playground needs one. Install:"
    for c in $choices
    do
      if [ "$i" = "1" ]; then echo "  $i) $(engine_label "$c")   ← default"; else echo "  $i) $(engine_label "$c")"; fi
      i=$((i+1))
    done
    echo "  s) skip, I will install one myself"
  } > /dev/tty
  while true
  do
    printf '%s' "❓ your choice [1]: " > /dev/tty
    IFS= read -r answer < /dev/tty || answer="s"
    [ -z "$answer" ] && answer=1
    case "$answer" in
      s|S|skip) return 0 ;;
    esac
    i=1
    for c in $choices
    do
      if [ "$answer" = "$i" ]; then echo "$c"; return 0; fi
      i=$((i+1))
    done
  done
}

install_engine_docker_linux() {
  local sudo id_like="" tmp
  sudo="$(sudo_cmd)"
  if [ -r /etc/os-release ]
  then
    id_like="$(. /etc/os-release; echo "${ID:-} ${ID_LIKE:-}")"
  fi
  case " $id_like " in
    *" ubuntu "*|*" debian "*|*" fedora "*|*" centos "*|*" rhel "*|*" raspbian "*) ;;
    *)
      logwarn "Docker's installer does not support this distribution ($id_like): install Docker Engine yourself, https://docs.docker.com/engine/install/"
      return 1
      ;;
  esac
  if ! command -v curl > /dev/null 2>&1
  then
    logwarn "curl is needed to install Docker Engine"
    return 1
  fi
  tmp="$(mktemp)"
  run curl -fsSL https://get.docker.com -o "$tmp" || { rm -f "$tmp"; logwarn "could not download https://get.docker.com"; return 1; }
  # the script uses sudo by itself when not run as root
  run sh "$tmp" || { rm -f "$tmp"; logwarn "the Docker Engine install failed: https://docs.docker.com/engine/install/"; return 1; }
  rm -f "$tmp"
  if [ -d /run/systemd/system ]
  then
    run $sudo systemctl enable --now docker
  else
    run $sudo service docker start || true
  fi
  if [ "$opt_dry_run" = "0" ]
  then
    local i=0
    while [ "$i" -lt 15 ] && ! $sudo docker info > /dev/null 2>&1
    do
      sleep 2
      i=$((i+1))
    done
    if $sudo docker info > /dev/null 2>&1
    then
      log_ok "Docker Engine is running"
    else
      logwarn "Docker Engine does not answer: sudo systemctl status docker"
    fi
  fi
  if [ "$(id -u)" != "0" ] && ! id -nG 2> /dev/null | grep -qw docker
  then
    run $sudo usermod -aG docker "$USER"
    docker_group_pending=1
    log "you are now in the docker group: it applies to new logins, log out and back in (or run: newgrp docker)"
  fi
}

install_engine_podman_macos() {
  local mem_gb cpus machine_mb prefix
  mem_gb=$(( $(sysctl -n hw.memsize 2> /dev/null || echo 0) / 1024 / 1024 / 1024 ))
  cpus="$(sysctl -n hw.ncpu 2> /dev/null || echo 4)"
  [ "$cpus" -gt 4 ] && cpus=4
  # 12GB for the machine, but leave at least 4GB to macOS
  machine_mb=12288
  if [ "$mem_gb" -gt 0 ] && [ $(( (mem_gb - 4) * 1024 )) -lt "$machine_mb" ]
  then
    machine_mb=$(( (mem_gb - 4) * 1024 ))
  fi
  if [ "$machine_mb" -lt 8192 ]
  then
    logwarn "this Mac has ${mem_gb}GB of memory: the podman machine gets ${machine_mb}MB, and the playground needs 8GB for most examples"
    [ "$machine_mb" -lt 4096 ] && machine_mb=4096
  fi

  run "$brew_bin" install podman docker docker-compose || { logwarn "brew install failed"; return 1; }
  # the docker CLI from brew only finds the compose plugin from ~/.docker/cli-plugins
  prefix="$("$brew_bin" --prefix)"
  run mkdir -p "$HOME/.docker/cli-plugins"
  run ln -sfn "$prefix/lib/docker/cli-plugins/docker-compose" "$HOME/.docker/cli-plugins/docker-compose"
  hash -r 2> /dev/null || true

  if [ "$opt_dry_run" = "1" ] || ! podman machine inspect podman-machine-default > /dev/null 2>&1
  then
    log "creating the podman machine: ${cpus} CPUs, ${machine_mb}MB of memory, 100GB of disk (downloads about 1GB)"
    run podman machine init --rootful --cpus "$cpus" --memory "$machine_mb" --disk-size 100 \
      || { logwarn "podman machine init failed"; return 1; }
  fi
  # 'playground switch-podman' starts the machine, creates a 'podman' docker context and ends with 'playground doctor'
  if [ "$opt_dry_run" = "1" ]
  then
    run playground switch-podman
    return 0
  fi
  if PATH="$(dirname "$bash4"):$install_dir/scripts/cli:$PATH" "$bash4" "$install_dir/scripts/cli/playground" switch-podman
  then
    doctor_done=1
  else
    logwarn "playground switch-podman failed: fix what it says above, then run it again"
  fi
}

install_engine_docker_desktop_macos() {
  local i
  logwarn "Docker Desktop needs a paid subscription in companies with more than 250 employees or \$10M revenue: check that your company has one"
  confirm "install Docker Desktop ($brew_bin install --cask docker-desktop)?" n || { log "skipped"; return 0; }
  run "$brew_bin" install --cask docker-desktop || { logwarn "brew install --cask docker-desktop failed: https://docs.docker.com/desktop/setup/install/mac-install/"; return 1; }
  run open -a Docker
  [ "$opt_dry_run" = "1" ] && return 0
  log "⏳ accept the Docker Subscription Service Agreement in the Docker Desktop window, waiting for the engine (5 minutes max)"
  hash -r 2> /dev/null || true
  i=0
  while [ "$i" -lt 60 ]
  do
    if command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1
    then
      log_ok "Docker Desktop is running"
      log "give it at least 8GB of memory: Docker Desktop > Settings > Resources (playground doctor checks it)"
      return 0
    fi
    sleep 5
    i=$((i+1))
  done
  logwarn "Docker Desktop did not answer within 5 minutes: finish its setup, then run: playground doctor"
}

setup_engine() {
  title "🐳 4/6 Container engine"
  detect_engine
  case "$engine_state" in
    running)
      log_ok "a container engine is running: nothing to install"
      return 0
      ;;
    stopped)
      logwarn "a container engine is installed but not reachable, not installing another one: $engine_hint"
      return 0
      ;;
  esac

  local choices engine=""
  choices="$(engine_choices)"
  # Homebrew only when an engine can be installed: asked interactively, or --engine podman|docker-desktop
  # (--yes alone installs no engine, --engine none neither)
  if [ "$os" = "macos" ] && [ -z "$brew_bin" ] && [ "$opt_engine" != "none" ] && { [ "$opt_yes" = "0" ] || [ -n "$opt_engine" ]; }
  then
    ensure_brew "a container engine (Podman or Docker Desktop)" || choices=""
  fi
  if [ -z "$choices" ]
  then
    case "$os" in
      wsl) logwarn "no container engine: install Docker Desktop for Windows with the WSL 2 integration, https://docs.docker.com/desktop/features/wsl/ (or enable systemd in /etc/wsl.conf and run this installer again for Docker Engine)" ;;
      macos) logwarn "no container engine, and Homebrew is not installed: install Docker Desktop (https://docs.docker.com/get-docker/) or Podman (https://podman.io)" ;;
      *) logwarn "no container engine: https://docs.docker.com/engine/install/" ;;
    esac
    return 0
  fi

  case "$opt_engine" in
    none)
      log "--engine none: not installing a container engine"
      return 0
      ;;
    "")
      if [ "$opt_yes" = "1" ]
      then
        logwarn "no container engine: --yes does not install one, pass --engine $(echo "$choices" | tr ' ' '|') to do it"
        return 0
      fi
      engine="$(choose_engine "$choices")"
      ;;
    *)
      case " $choices " in
        *" $opt_engine "*) engine="$opt_engine" ;;
        *) logerror "--engine $opt_engine cannot be installed here, choices: $choices none"; return 0 ;;
      esac
      ;;
  esac
  if [ -z "$engine" ]
  then
    if [ "$os" = "macos" ]
    then
      logwarn "skipped: install Docker Desktop or Podman yourself, https://docs.docker.com/get-docker/"
    else
      logwarn "skipped: install Docker Engine yourself, https://docs.docker.com/engine/install/"
    fi
    return 0
  fi

  case "$engine" in
    docker) install_engine_docker_linux ;;
    podman) install_engine_podman_macos ;;
    docker-desktop) install_engine_docker_desktop_macos ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------
# 5. shell startup file
# ---------------------------------------------------------------------------------------------------------------------

# prints the content of the block for a shell (zsh|bash)
# a line of the block already in the shell startup file, found by its trailing comment
previous_block_line() {
  local rc
  rc="$(rc_files_for_shell)"
  [ -n "$rc" ] && [ -f "$rc" ] || return 1
  awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '$0 == b { in_block = 1; next } $0 == e { in_block = 0 } in_block' "$rc" \
    | grep -F -- "$1" | head -1 | grep .
}

rc_block() {
  local shell_name="$1" line
  echo "$MARKER_BEGIN"
  echo "# added by ${KDP_DOCS_URL}/install.sh, remove with: curl -fsSL ${KDP_DOCS_URL}/install.sh | bash -s -- --uninstall"
  # the PATH lines are computed from the PATH of this run, which already includes what the block added in a
  # previous run: keep the lines of the previous block, otherwise a second run from a new terminal removes them
  if [ "$brew_shellenv_needed" = "1" ]
  then
    echo "eval \"\$($brew_bin shellenv)\"   # Homebrew: bash 4+, fzf, Confluent CLI"
  elif line="$(previous_block_line "# Homebrew")"
  then
    echo "$line"
  fi
  if ! path_bash_is_4 && [ -n "$bash4" ]
  then
    echo "export PATH=\"$(dirname "$bash4"):\$PATH\"   # bash 4+, needed by playground"
  elif line="$(previous_block_line "# bash 4+")"
  then
    echo "$line"
  fi
  if [ -n "$confluent_bin_dir" ]
  then
    echo "export PATH=\"$confluent_bin_dir:\$PATH\"   # Confluent CLI"
  elif line="$(previous_block_line "# Confluent CLI")"
  then
    echo "$line"
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
  title "🦶 5/6 Shell setup (PATH and completion)"
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
# 6. doctor
# ---------------------------------------------------------------------------------------------------------------------

run_doctor() {
  title "🩺 6/6 playground doctor"
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
  if [ "$doctor_done" = "1" ]
  then
    log_ok "already run by playground switch-podman above"
    return 0
  fi
  hash -r 2> /dev/null || true
  if ! command -v docker > /dev/null 2>&1
  then
    logwarn "skipped: install Docker Desktop or Podman first, then run: playground doctor"
    return 0
  fi
  local doctor_cmd
  doctor_cmd="PATH=\"$(dirname "$bash4"):$install_dir/scripts/cli:\$PATH\" \"$bash4\" \"$install_dir/scripts/cli/playground\" doctor"
  if [ "$docker_group_pending" = "1" ] && command -v sg > /dev/null 2>&1
  then
    # this session is not in the docker group yet
    doctor_cmd="sg docker -c '$doctor_cmd'"
  fi
  if sh -c "$doctor_cmd"
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
  log "Docker / Podman, the Confluent CLI, bash, fzf and git stay installed: remove them with brew or your package manager (or rm ~/.local/bin/confluent) if you no longer need them"
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
  setup_engine
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
