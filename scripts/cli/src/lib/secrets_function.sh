################################################################################
# 🔐 playground secrets — credentials required by examples
#
# Secrets are stored OUTSIDE the repository, in $PLAYGROUND_SECRETS_DIR
# (default $HOME/.config/kafka-docker-playground), so that they survive
# `git clean -fdx`, are never picked up by `git add -A` and never end up in a
# `playground repro export` archive.
#
# Two stores, same INI format, one [profile] section per profile:
#
#   secrets.ini (0600) NAME = <backend reference>   (or the value itself with
#                                                    the `file` backend)
#   env.ini     (0644) NAME = <plain value>         non sensitive variables
#                                                   (GCP_PROJECT, AWS_REGION…)
#
# They are deliberately NOT read with lib/ini.sh: ini_load() evals any value
# containing a `$`, which would corrupt — or execute — a password.
################################################################################

PLAYGROUND_SECRETS_SERVICE="kafka-docker-playground"

function get_secrets_dir () {
  local dir="${PLAYGROUND_SECRETS_DIR:-$HOME/.config/kafka-docker-playground}"
  if [ ! -d "$dir" ]
  then
    mkdir -p "$dir"
    chmod 0700 "$dir"
  fi
  echo "$dir"
}

function get_secrets_file () {
  echo "$(get_secrets_dir)/secrets.ini"
}

function get_env_file () {
  echo "$(get_secrets_dir)/env.ini"
}

function get_active_secret_profile () {
  if [ -n "${PLAYGROUND_SECRETS_PROFILE:-}" ]
  then
    echo "$PLAYGROUND_SECRETS_PROFILE"
    return
  fi
  if [ -z "${PLAYGROUND_SECRETS_PROFILE_CACHE:-}" ]
  then
    PLAYGROUND_SECRETS_PROFILE_CACHE=$(playground config get secrets.profile 2>/dev/null)
    [ -z "$PLAYGROUND_SECRETS_PROFILE_CACHE" ] && PLAYGROUND_SECRETS_PROFILE_CACHE="default"
  fi
  echo "$PLAYGROUND_SECRETS_PROFILE_CACHE"
}

#
# Backend used when storing a new secret.
#
# Only the backends that can be used without any interactive setup are picked
# automatically. `op` and `vault` must be selected explicitly with
# `playground secrets backend <name>`, so that we never block on a vault
# unlock prompt in the middle of an example.
#
function get_secret_backend () {
  if [ -n "${PLAYGROUND_SECRETS_BACKEND:-}" ]
  then
    echo "$PLAYGROUND_SECRETS_BACKEND"
    return
  fi
  if [ -z "${PLAYGROUND_SECRETS_BACKEND_CACHE:-}" ]
  then
    PLAYGROUND_SECRETS_BACKEND_CACHE=$(playground config get secrets.backend 2>/dev/null)
    if [ -z "$PLAYGROUND_SECRETS_BACKEND_CACHE" ]
    then
      if [[ "$OSTYPE" == "darwin"* ]] && command -v security > /dev/null 2>&1
      then
        PLAYGROUND_SECRETS_BACKEND_CACHE="keychain"
      elif command -v secret-tool > /dev/null 2>&1
      then
        PLAYGROUND_SECRETS_BACKEND_CACHE="secret-tool"
      elif command -v pass > /dev/null 2>&1
      then
        PLAYGROUND_SECRETS_BACKEND_CACHE="pass"
      else
        PLAYGROUND_SECRETS_BACKEND_CACHE="file"
      fi
    fi
  fi
  echo "$PLAYGROUND_SECRETS_BACKEND_CACHE"
}

################################################################################
# store primitives (no eval, ever)
################################################################################

# dump a store as: profile<TAB>name<TAB>value
function secret_store_dump () {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    /^[ \t]*[;#]/ { next }
    /^[ \t]*\[.*\][ \t]*$/ {
      section=$0
      sub(/^[ \t]*\[[ \t]*/, "", section)
      sub(/[ \t]*\][ \t]*$/, "", section)
      next
    }
    {
      idx=index($0, "=")
      if (idx == 0) next
      key=substr($0, 1, idx-1)
      val=substr($0, idx+1)
      gsub(/^[ \t]+|[ \t]+$/, "", key)
      gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (key == "") next
      if (section == "") section="default"
      printf "%s\t%s\t%s\n", section, key, val
    }
  ' "$file"
}

function secret_store_render () {
  sort -t"$(printf '\t')" -k1,1 -k2,2 | awk -F"\t" '
    $1 != section { if (section != "") printf "\n"; printf "[%s]\n", $1; section=$1 }
    { printf "%s = %s\n", $2, $3 }
  '
}

function secret_store_get () {
  local file="$1"
  local profile="$2"
  local name="$3"

  local value
  value=$(secret_store_dump "$file" | awk -F"\t" -v p="$profile" -v n="$name" '$1==p && $2==n { print $3; exit }')
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

function secret_store_set () {
  local file="$1"
  local profile="$2"
  local name="$3"
  local value="$4"
  local mode="$5"

  local tmp="${file}.tmp.$$"
  {
    secret_store_dump "$file" | awk -F"\t" -v p="$profile" -v n="$name" '!($1==p && $2==n)'
    printf "%s\t%s\t%s\n" "$profile" "$name" "$value"
  } | secret_store_render > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$file"
}

function secret_store_del () {
  local file="$1"
  local profile="$2"
  local name="$3"
  local mode="$4"

  [ -f "$file" ] || return 0
  local tmp="${file}.tmp.$$"
  secret_store_dump "$file" | awk -F"\t" -v p="$profile" -v n="$name" '!($1==p && $2==n)' | secret_store_render > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$file"
}

# all names known for a profile, secrets first then plain variables
function secret_store_names () {
  local profile="${1:-$(get_active_secret_profile)}"
  {
    secret_store_dump "$(get_secrets_file)" | awk -F"\t" -v p="$profile" '$1==p { print $2 }'
    secret_store_dump "$(get_env_file)"     | awk -F"\t" -v p="$profile" '$1==p { print $2 }'
  } | sort -u
}

function secret_store_profiles () {
  {
    echo "default"
    secret_store_dump "$(get_secrets_file)" | awk -F"\t" '{ print $1 }'
    secret_store_dump "$(get_env_file)"     | awk -F"\t" '{ print $1 }'
  } | sort -u
}

################################################################################
# backends
################################################################################

#
# Is `op` usable right now? `op whoami` alone is not enough: with the desktop
# app integration it answers `account is not signed in` until something in
# this terminal session has asked the app for an authorization, which
# `op whoami` itself never does (`op vault list`, `op read`… do). So when it
# fails, `op signin` asks the app once (Touch ID, or nothing if the app is
# already unlocked), and `op whoami` is asked again.
#
# Not with a service account: the token is the only credential, there is
# nothing to sign in to. stdin is closed so that a manually added account
# (`op account add`, no app) fails fast instead of waiting for a password.
#
function op_signed_in () {
  if op whoami > /dev/null 2>&1
  then
    return 0
  fi
  if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]
  then
    return 1
  fi
  op signin < /dev/null > /dev/null 2>&1 || return 1
  op whoami > /dev/null 2>&1
}

#
# 1Password vault the items are created in. `Private` is the vault every
# account has, so it is the default; a shared vault is often a better choice
# for a team, hence the override.
#
function get_op_vault () {
  if [ -n "${PLAYGROUND_OP_VAULT:-}" ]
  then
    echo "$PLAYGROUND_OP_VAULT"
    return
  fi
  local vault
  vault=$(playground config get secrets.op-vault 2>/dev/null)
  echo "${vault:-Private}"
}

#
# Title of the item we create in 1Password.
#
# No space and no slash, so that the resulting `op://<vault>/<title>/password`
# reference can be copied and pasted without quoting. The `kdp-` prefix is also
# what tells us, on `secrets unset`, whether we created the item or whether the
# user linked one of their own.
#
function get_op_item_title () {
  local profile="$1"
  local name="$2"
  echo "kdp-${profile}-${name}"
}

#
# Store a value and echo back the reference to keep in secrets.ini.
#
# ⚠️ keychain/secret-tool/pass/op all take the value on their command line, so
# it is briefly visible in `ps` on a multi-user machine. That is a limitation of
# those tools, not of this store.
#
function secret_backend_put () {
  local backend="$1"
  local profile="$2"
  local name="$3"
  local value="$4"

  # stdout is the reference, so every message here has to go to stderr
  case "$backend" in
    keychain)
      if ! security add-generic-password -U -s "$PLAYGROUND_SECRETS_SERVICE" -a "${profile}:${name}" -w "$value" > /dev/null 2>&1
      then
        logerror "❌ could not store $name in the macOS keychain" >&2
        return 1
      fi
      echo "keychain:${profile}:${name}"
    ;;
    secret-tool)
      if ! printf '%s' "$value" | secret-tool store --label="${PLAYGROUND_SECRETS_SERVICE} ${name}" service "$PLAYGROUND_SECRETS_SERVICE" profile "$profile" name "$name"
      then
        logerror "❌ could not store $name with secret-tool" >&2
        return 1
      fi
      echo "secret-tool:${profile}:${name}"
    ;;
    pass)
      if ! printf '%s\n' "$value" | pass insert -m -f "${PLAYGROUND_SECRETS_SERVICE}/${profile}/${name}" > /dev/null 2>&1
      then
        logerror "❌ could not store $name with pass" >&2
        return 1
      fi
      echo "pass:${PLAYGROUND_SECRETS_SERVICE}/${profile}/${name}"
    ;;
    op)
      local vault title op_error
      vault=$(get_op_vault)
      title=$(get_op_item_title "$profile" "$name")

      if ! op_signed_in
      then
        logerror "❌ not signed in to 1Password, cannot store $name" >&2
        logerror "👉 enable 'Integrate with 1Password CLI' in the desktop app, or run: eval \$(op signin)" >&2
        return 1
      fi

      if op item get "$title" --vault "$vault" > /dev/null 2>&1
      then
        if ! op_error=$(op item edit "$title" --vault "$vault" "password=${value}" < /dev/null 2>&1 > /dev/null)
        then
          logerror "❌ could not update 1Password item $title: $op_error" >&2
          return 1
        fi
      else
        if ! op_error=$(op item create --category Password --vault "$vault" --title "$title" \
            --tags "$PLAYGROUND_SECRETS_SERVICE" "password=${value}" < /dev/null 2>&1 > /dev/null)
        then
          logerror "❌ could not create 1Password item $title in vault $vault: $op_error" >&2
          return 1
        fi
      fi
      echo "op://${vault}/${title}/password"
    ;;
    vault)
      logerror "❌ backend vault is reference-only, it cannot create a secret" >&2
      logerror "👉 store the secret in Vault, then run: playground secrets link $name vault://<path>#<field>" >&2
      return 1
    ;;
    file)
      # the value itself is the reference
      printf '%s' "$value"
    ;;
    *)
      logerror "❌ unknown secrets backend $backend" >&2
      return 1
    ;;
  esac
}

#
# Write a new value into the item an existing reference already points at, and
# echo that reference back unchanged.
#
# Rotation must not move a secret. secret_backend_put() derives the location
# from the *configured* backend plus the kdp- naming convention, which is right
# for a brand new secret and wrong for one that already exists: on a machine
# where `secrets backend` says keychain but the reference says op://, it would
# write the new value to the keychain, rewrite the reference, and leave the
# 1Password item holding the old password — silently, and only on that machine.
#
# It also matters for `secrets link`, where the reference points at an item the
# user named themselves, in a vault of their choosing. Only the reference knows
# where that is.
#
function secret_backend_update () {
  local ref="$1"
  local value="$2"

  # stdout is the reference, so every message here has to go to stderr
  case "$ref" in
    keychain:*)
      if ! security add-generic-password -U -s "$PLAYGROUND_SECRETS_SERVICE" -a "${ref#keychain:}" -w "$value" > /dev/null 2>&1
      then
        logerror "❌ could not update $ref in the macOS keychain" >&2
        return 1
      fi
    ;;
    secret-tool:*)
      local rest="${ref#secret-tool:}"
      if ! printf '%s' "$value" | secret-tool store --label="${PLAYGROUND_SECRETS_SERVICE} ${rest#*:}" \
          service "$PLAYGROUND_SECRETS_SERVICE" profile "${rest%%:*}" name "${rest#*:}"
      then
        logerror "❌ could not update $ref with secret-tool" >&2
        return 1
      fi
    ;;
    pass:*)
      if ! printf '%s\n' "$value" | pass insert -m -f "${ref#pass:}" > /dev/null 2>&1
      then
        logerror "❌ could not update $ref with pass" >&2
        return 1
      fi
    ;;
    op://*)
      #
      # Split op://<vault>/<item>/<field> and edit that exact field, rather than
      # recomputing a location from the configured vault and the kdp- title.
      #
      local rest="${ref#op://}"
      local vault="${rest%%/*}"
      rest="${rest#*/}"
      local item="${rest%%/*}"
      local field="${rest#*/}"
      [ "$field" == "$item" ] && field="password"

      local op_error
      if ! op_error=$(op item edit "$item" --vault "$vault" "${field}=${value}" < /dev/null 2>&1 > /dev/null)
      then
        logerror "❌ could not update 1Password item $item in vault $vault: $op_error" >&2
        logerror "👉 a service account token needs write_items on that vault to rotate a password" >&2
        return 1
      fi
    ;;
    vault://*)
      logerror "❌ $ref points at Vault, which playground never writes to" >&2
      logerror "👉 update the secret in Vault directly, the reference stays valid" >&2
      return 1
    ;;
    *)
      # `file` backend: the reference *is* the value
      printf '%s' "$value"
      return 0
    ;;
  esac

  printf '%s' "$ref"
}

function secret_backend_del () {
  local ref="$1"

  case "$ref" in
    keychain:*)
      security delete-generic-password -s "$PLAYGROUND_SECRETS_SERVICE" -a "${ref#keychain:}" > /dev/null 2>&1
    ;;
    secret-tool:*)
      local rest="${ref#secret-tool:}"
      secret-tool clear service "$PLAYGROUND_SECRETS_SERVICE" profile "${rest%%:*}" name "${rest#*:}" > /dev/null 2>&1
    ;;
    pass:*)
      pass rm -f "${ref#pass:}" > /dev/null 2>&1
    ;;
    op://*)
      #
      # Only touch the items we created ourselves. A reference added with
      # `playground secrets link` points at an item the user already had, and
      # forgetting a variable here must never destroy it.
      #
      local rest="${ref#op://}"
      local vault="${rest%%/*}"
      rest="${rest#*/}"
      local title="${rest%%/*}"
      case "$title" in
        kdp-*)
          if ! op item delete "$title" --vault "$vault" --archive > /dev/null 2>&1
          then
            logwarn "⚠️ could not archive the 1Password item $title, remove it yourself if needed"
          fi
        ;;
        *)
          logwarn "🔗 $ref was linked, not created by playground: the 1Password item is left untouched"
        ;;
      esac
    ;;
    vault://*)
      logwarn "🔗 $ref was linked, not created by playground: the Vault secret is left untouched"
    ;;
  esac
  return 0
}

#
# Check once, before a batch of reads or writes, that the backend is usable at
# all. Without it a `secrets import` of twenty variables prints the same
# "not signed in" error twenty times.
#
# Deliberately cheap: only the checks that are local or answered from the
# already open session. `op whoami` is ~0.07s (see op_signed_in()), while `op vault get` is a real
# round trip and costs several seconds — see secret_backend_vault_ready().
#
function secret_backend_ready () {
  local backend="${1:-$(get_secret_backend)}"

  case "$backend" in
    op)
      if ! command -v op > /dev/null 2>&1
      then
        logerror "❌ the 1Password CLI (op) is not installed"
        logerror "👉 brew install 1password-cli"
        return 1
      fi
      if ! op_signed_in
      then
        logerror "❌ not signed in to 1Password"
        logerror "👉 enable 'Integrate with 1Password CLI' in the desktop app (Settings > Developer), or run: eval \$(op signin)"
        return 1
      fi
    ;;
    pass)
      if ! pass ls > /dev/null 2>&1
      then
        logerror "❌ the pass store is not initialised"
        logerror "👉 pass init <gpg-id>"
        return 1
      fi
    ;;
  esac
  return 0
}

#
# The expensive half of the check above: does the configured vault actually
# exist and is it readable.
#
# Worth several seconds, so only the commands that are about to *write* call it
# up front. Read paths call it lazily, to explain a lookup that came back empty
# rather than to gate one that would have worked.
#
function secret_backend_vault_ready () {
  local backend="${1:-$(get_secret_backend)}"

  case "$backend" in
    op)
      local vault
      vault=$(get_op_vault)
      if ! op vault get "$vault" > /dev/null 2>&1
      then
        logerror "❌ 1Password vault $vault is not readable with your current session"
        logerror "👉 playground config set secrets.op-vault <vault>"
        return 1
      fi
    ;;
  esac
  return 0
}

#
# Both halves, for the commands that write.
#
function secret_backend_writable () {
  local backend="${1:-$(get_secret_backend)}"

  secret_backend_ready "$backend" || return 1
  secret_backend_vault_ready "$backend" || return 1
  return 0
}

function secret_reference_backend () {
  case "$1" in
    keychain:*)    echo "keychain" ;;
    secret-tool:*) echo "secret-tool" ;;
    pass:*)        echo "pass" ;;
    op://*)        echo "op" ;;
    vault://*)     echo "vault" ;;
    *)             echo "file" ;;
  esac
}

function secret_resolve_reference () {
  local ref="$1"

  case "$ref" in
    keychain:*)
      security find-generic-password -s "$PLAYGROUND_SECRETS_SERVICE" -a "${ref#keychain:}" -w 2>/dev/null
    ;;
    secret-tool:*)
      local rest="${ref#secret-tool:}"
      secret-tool lookup service "$PLAYGROUND_SECRETS_SERVICE" profile "${rest%%:*}" name "${rest#*:}" 2>/dev/null
    ;;
    pass:*)
      pass show "${ref#pass:}" 2>/dev/null | head -1
    ;;
    op://*)
      op read "$ref" 2>/dev/null
    ;;
    vault://*)
      local path="${ref#vault://}"
      local field="${path##*#}"
      path="${path%#*}"
      vault kv get -field="$field" "$path" 2>/dev/null
    ;;
    *)
      printf '%s' "$ref"
    ;;
  esac
}

################################################################################
# lookup
################################################################################

# echo the reference stored for a name, searching the active profile then the
# default one, secrets store then plain variables store
function secret_lookup_reference () {
  local name="$1"
  local profile="${2:-$(get_active_secret_profile)}"

  local file
  for file in "$(get_secrets_file)" "$(get_env_file)"
  do
    local ref
    if ref=$(secret_store_get "$file" "$profile" "$name")
    then
      printf '%s' "$ref"
      return 0
    fi
    if [ "$profile" != "default" ] && ref=$(secret_store_get "$file" "default" "$name")
    then
      printf '%s' "$ref"
      return 0
    fi
  done
  return 1
}

#
# Where a variable is kept: "secret" (secrets.ini, value in the backend),
# "plain" (env.ini, value in clear text) or nothing when it is not stored.
#
# Since --secret and --plain let the user override the name-based guess, this
# is what the display commands have to use, not is_secret_env_var_name().
#
function secret_store_location () {
  local name="$1"
  local profile="${2:-$(get_active_secret_profile)}"

  local file location
  for location in secret plain
  do
    if [ "$location" == "secret" ]
    then
      file="$(get_secrets_file)"
    else
      file="$(get_env_file)"
    fi
    if secret_store_get "$file" "$profile" "$name" > /dev/null
    then
      echo "$location"
      return 0
    fi
    if [ "$profile" != "default" ] && secret_store_get "$file" "default" "$name" > /dev/null
    then
      echo "$location"
      return 0
    fi
  done
  return 1
}

################################################################################
# prefetch
################################################################################

#
# Values already resolved in this process, and the names we have already tried.
# Two arrays and not one, because "resolved to nothing" has to be remembered as
# well, otherwise a missing variable is looked up again on every call.
#
declare -gA PLAYGROUND_SECRET_CACHE 2> /dev/null || true
declare -gA PLAYGROUND_SECRET_CACHE_TRIED 2> /dev/null || true

#
# Resolve a whole list of variables at once, in parallel, into the cache above.
#
# Every backend resolution is an out of process round trip: `op read` alone is
# ~1.5s, and they are completely independent of each other. Doing them one
# after the other is what made `playground secrets env` take tens of seconds on
# an example needing a handful of credentials. Firing them together turns
# N x 1.5s into roughly 1.5s.
#
# Bounded, because `secrets env --all` covers the whole store and no backend
# enjoys a hundred simultaneous clients — and with a locked session each one
# could raise its own unlock prompt. 16 is where 1Password stops getting
# meaningfully faster for the size of store this is used with (57 `op read`:
# 5.7s at 8, 3.2s at 16, 2.0s at 32) while still spawning a sane number of
# processes. Most examples need a handful of variables, so the cap rarely bites.
#
function secret_prefetch () {
  local profile="${1:-$(get_active_secret_profile)}"
  shift

  local tmp_dir
  tmp_dir=$(mktemp -d)
  chmod 0700 "$tmp_dir"

  local pending=()
  local name
  for name in "$@"
  do
    [ -n "${PLAYGROUND_SECRET_CACHE_TRIED[$name]:-}" ] && continue
    #
    # An exported value wins, same rule as secret_get(); no point spawning a
    # backend call for it.
    #
    [ -n "${!name:-}" ] && continue
    pending+=("$name")
  done

  #
  # Resolve the first one on its own, before fanning out.
  #
  # A locked backend authorises *per client process*: 1Password's desktop app
  # integration validates the code signature of every `op` it is talking to and
  # pops "Allow <app> to get CLI access" for one it does not know yet. Sixteen
  # of them starting at the same millisecond means sixteen of those dialogs.
  # The first call alone takes the prompt and unlocks the session; the rest then
  # find it already open and stay silent.
  #
  local value
  if [ ${#pending[@]} -gt 0 ]
  then
    name="${pending[0]}"
    if value=$(secret_get_from_store "$name" "$profile")
    then
      printf '%s' "$value" > "$tmp_dir/$name"
    fi
    pending=("${pending[@]:1}")
  fi

  local nb_running=0
  for name in "${pending[@]}"
  do
    (
      if value=$(secret_get_from_store "$name" "$profile")
      then
        printf '%s' "$value" > "$tmp_dir/$name"
      fi
    ) &

    nb_running=$((nb_running+1))
    if [ $nb_running -ge 16 ]
    then
      wait
      nb_running=0
    fi
  done
  wait

  for name in "$@"
  do
    [ -n "${PLAYGROUND_SECRET_CACHE_TRIED[$name]:-}" ] && continue
    [ -n "${!name:-}" ] && continue

    PLAYGROUND_SECRET_CACHE_TRIED[$name]=1
    if [ -f "$tmp_dir/$name" ]
    then
      PLAYGROUND_SECRET_CACHE[$name]=$(< "$tmp_dir/$name")
    fi
  done

  rm -rf "$tmp_dir"
}

#
# Resolve a variable. A real environment variable always wins, so
# `export FOO=bar`, `source secret.properties` and GitHub Actions secrets keep
# working exactly as before.
#
function secret_get () {
  local name="$1"
  local profile="${2:-$(get_active_secret_profile)}"

  if [ -n "${!name:-}" ]
  then
    printf '%s' "${!name}"
    return 0
  fi

  secret_get_from_store "$name" "$profile"
}

#
# Same thing, but ignoring the environment.
#
# For anything that copies a value into another system of record — GitHub
# Actions secrets, mainly — the store has to be the source of truth. A shell
# that still has an old `source secret.properties` in it would otherwise push
# the value you just rotated away.
#
function secret_get_from_store () {
  local name="$1"
  local profile="${2:-$(get_active_secret_profile)}"

  if [ -n "${PLAYGROUND_SECRET_CACHE_TRIED[$name]:-}" ]
  then
    [ -n "${PLAYGROUND_SECRET_CACHE[$name]:-}" ] || return 1
    printf '%s' "${PLAYGROUND_SECRET_CACHE[$name]}"
    return 0
  fi

  local ref
  ref=$(secret_lookup_reference "$name" "$profile") || return 1
  [ -n "$ref" ] || return 1

  local value
  value=$(secret_resolve_reference "$ref" || true)
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

################################################################################
# helpers
################################################################################

#
# Same classification as the fzf preview in `playground run`: a name that looks
# like a credential goes to the secrets store, anything else to the plain
# variables store.
#
function is_secret_env_var_name () {
  case "$1" in
    *PASSWORD*|*PASSPHRASE*|*SECRET*|*TOKEN*|*KEY*|*CREDS*|*PWD*) return 0 ;;
    #
    # CONFLUENT_LICENSE is a signed JWT, not a setting: whoever holds it can run
    # the licensed components. None of the words above appear in it, so without
    # this line it is filed as a plain variable and written in clear into
    # env.ini, which is mode 0644 while secrets.ini is 0600.
    #
    *LICENSE*|*LICENCE*) return 0 ;;
  esac
  return 1
}

#
# Render <name>='<value>' for a file that a shell is going to source.
#
# Anything written as a bare name=value breaks as soon as the value holds a
# space, a `$`, a brace or a quote: `FOO=a b` runs `b` as a command,
# `FOO=${x}` is expanded, `FOO=}` is a parse error. Single quotes make the
# value literal; the only character needing care inside them is the single
# quote itself, closed and reopened around an escaped one.
#
function secret_shell_assignment () {
  local name="$1"
  local value="$2"

  printf "%s='%s'\n" "$name" "${value//\'/\'\\\'\'}"
}

################################################################################
# push to a remote machine (playground ec2 push-secrets, playground codespace push-secrets)
################################################################################

#
# Build the payload sent to a remote machine, one line per variable of a profile.
#
#   $1  profile
#   $2  all | secret | plain: every variable, or only the credentials, or only
#       the plain variables (where secret_store_location files them)
#   $3  shell | import:
#       shell   <name>='<value>' (secret_shell_assignment), for a file that a
#               shell sources (playground ec2 push-secrets)
#       import  <name>="<value>", for 'playground secrets import' on the remote
#               side (playground codespace push-secrets). import strips the outer
#               double quotes and interprets nothing inside, so any value comes
#               back exactly (a value cannot hold a newline), whatever the
#               version of the playground CLI over there: the '\'' escape of the
#               shell format is only understood by a recent one
#
# It reads the store and not the environment, like 'playground secrets
# push-github': the remote side must get what the store holds, not what the
# shell launching the command still has exported.
#
# Values are resolved in parallel (secret_prefetch): one 'op read' after the
# other made a 100 variable profile take minutes. Everything is built in memory
# before contacting anything, so a locked 1Password fails before a half written
# file lands on the remote side.
#
# Sets SECRET_PAYLOAD, SECRET_PAYLOAD_NB (resolved) and SECRET_PAYLOAD_NB_FAILED,
# globals and not stdout: the prefetch cache lives in this shell, a $(...)
# subshell would lose it.
#
function secret_build_payload () {
  local profile="$1"
  local which="${2:-all}"
  local format="${3:-shell}"
  local name value location
  local names=()

  SECRET_PAYLOAD=""
  SECRET_PAYLOAD_NB=0
  SECRET_PAYLOAD_NB_FAILED=0

  for name in $(secret_store_names "$profile")
  do
    if [ "$which" != "all" ]
    then
      location=$(secret_store_location "$name" "$profile" || true)
      [ "$location" == "$which" ] || continue
    fi
    names+=("$name")
  done
  [ ${#names[@]} -gt 0 ] || return 0

  secret_prefetch "$profile" "${names[@]}"
  for name in "${names[@]}"
  do
    if value=$(secret_get_from_store "$name" "$profile")
    then
      if [ "$format" == "import" ]
      then
        SECRET_PAYLOAD="${SECRET_PAYLOAD}${name}=\"${value}\""$'\n'
      else
        SECRET_PAYLOAD="${SECRET_PAYLOAD}$(secret_shell_assignment "$name" "$value")"$'\n'
      fi
      SECRET_PAYLOAD_NB=$((SECRET_PAYLOAD_NB+1))
    else
      logwarn "⚠️ $name could not be resolved, skipped"
      SECRET_PAYLOAD_NB_FAILED=$((SECRET_PAYLOAD_NB_FAILED+1))
    fi
  done
}

#
# Credentials that cannot live in the secrets store, because they are multi
# line files and not name=value pairs. They used to travel inside secrets.tar,
# which the cloud formation bootstrap decrypted on the instance; sending them
# over ssh instead is what makes that tarball removable.
#
# Each entry is <local file at repo root>:<remote path under $HOME>:<mode>.
#
# The two aws ones are bind mounted into the connect container by the
# *-with-assuming-iam-role examples, hence the world readable mode: the uid
# inside the container is not the uid of the remote user.
#
SECRET_PUSH_FILES=(
  "aws_credentials_with_assuming_iam_role:.aws/credentials-with-assuming-iam-role:644"
  "aws_credentials_aws_account_with_assume_role:.aws/credentials_aws_account_with_assume_role:644"
  "github_ssh_key_file:.ssh/id_rsa:600"
)

# The entries of SECRET_PUSH_FILES whose local file exists, into SECRET_PUSH_AVAILABLE_FILES
function secret_push_available_files () {
  local entry local_file
  SECRET_PUSH_AVAILABLE_FILES=()
  for entry in "${SECRET_PUSH_FILES[@]}"
  do
    local_file="$root_folder/${entry%%:*}"
    if [ -f "$local_file" ]
    then
      SECRET_PUSH_AVAILABLE_FILES+=("$entry")
    else
      logwarn "⚠️ $local_file does not exist, it will not be sent"
    fi
  done
}

#
# The remote shell script that writes stdin into ~/<remote path> with <mode>.
#
# umask first so the file is never readable by anyone else while it is being
# written, then the final mode once it is complete.
#
# ~/.ssh is created by root in the cloud formation user data, and only its
# content is given back to the user, so a plain `cat > ~/.ssh/id_rsa` fails with
# "Permission denied" on every ec2 instance created before that was fixed. Take
# ownership of the directory with sudo (passwordless on the playground ec2
# instances and in a codespace) when it is not writable.
#
# The content lands in a temporary file next to its destination and is renamed
# once complete: never a half written credential file, and the rename also
# replaces a destination owned by root.
#
# A missing final newline is added: ssh-keygen (and therefore git over ssh)
# rejects a private key whose last line is not terminated with "Load key:
# invalid format", and so do most credential parsers.
#
function secret_push_file_remote_script () {
  local remote_path="$1"
  local mode="$2"
  printf 'umask 077
dir="$HOME/%s"
mkdir -p "$dir" 2>/dev/null || sudo mkdir -p "$dir"
[ -w "$dir" ] || sudo chown -R "$(id -u):$(id -g)" "$dir"
tmp=$(mktemp "$dir/.playground-push.XXXXXX") || exit 1
cat > "$tmp" || { rm -f "$tmp"; exit 1; }
[ -n "$(tail -c1 "$tmp")" ] && echo >> "$tmp"
chmod %s "$tmp" && mv -f "$tmp" "$HOME/%s" || { rm -f "$tmp"; exit 1; }' \
    "$(dirname "$remote_path")" "$mode" "$remote_path"
}

function secret_sha256 () {
  if command -v shasum > /dev/null 2>&1
  then
    printf '%s' "$1" | shasum -a 256 | cut -c1-8
  elif command -v sha256sum > /dev/null 2>&1
  then
    printf '%s' "$1" | sha256sum | cut -c1-8
  else
    echo "????????"
  fi
}

#
# A value is never printed: this returns just enough to answer "is this the
# token I rotated yesterday?" without putting it in scrollback.
#
function secret_fingerprint () {
  local value="$1"
  local len=${#value}

  if [ "$len" -eq 0 ]
  then
    echo "(empty)"
    return
  fi

  local hash
  hash=$(secret_sha256 "$value")
  if [ "$len" -le 8 ]
  then
    echo "**** (${len} chars, sha256:${hash})"
  else
    echo "****${value: -4} (${len} chars, sha256:${hash})"
  fi
}

function read_secret_value_interactively () {
  local name="$1"
  local value=""

  if [ ! -t 0 ]
  then
    logerror "❌ no terminal available to prompt for $name, use --value"
    return 1
  fi
  >&2 printf '🔐 Enter value for %s (input hidden): ' "$name"
  read -r -s value
  >&2 echo ""
  if [ -z "$value" ]
  then
    logerror "❌ empty value, nothing stored"
    return 1
  fi
  printf '%s' "$value"
}

#
# $4 forces the classification: "secret" or "plain". Left empty, the variable
# name decides, which is what `secrets import` relies on to sort a whole
# secret.properties in one pass.
#
function secret_store_value () {
  local name="$1"
  local value="$2"
  local profile="${3:-$(get_active_secret_profile)}"
  local force="${4:-}"

  if [[ "$value" == *$'\n'* ]]
  then
    logerror "❌ $name contains a newline, which the store does not support"
    logerror "👉 for a multi-line credential (a key file, a PEM), point the example at a file path instead"
    return 1
  fi

  # an 'if' on purpose: a bare '&&' would make the case statement return 1 and
  # trip errexit when the name is not a credential
  local sensitive=1
  case "$force" in
    secret) sensitive=0 ;;
    plain)  sensitive=1 ;;
    *)
      if is_secret_env_var_name "$name"
      then
        sensitive=0
      fi
    ;;
  esac

  if [ $sensitive -eq 0 ]
  then
    local ref old_ref backend
    if old_ref=$(secret_store_get "$(get_secrets_file)" "$profile" "$name")
    then
      #
      # Already stored: rotate it in place. The reference, not the configured
      # backend, decides where the value goes — see secret_backend_update().
      #
      backend=$(secret_reference_backend "$old_ref")
      ref=$(secret_backend_update "$old_ref" "$value") || return 1
    else
      backend=$(get_secret_backend)
      ref=$(secret_backend_put "$backend" "$profile" "$name" "$value") || return 1
    fi
    secret_store_set "$(get_secrets_file)" "$profile" "$name" "$ref" "0600"
    #
    # A variable promoted from --plain to --secret would otherwise keep its
    # clear text copy in env.ini, which defeats the whole point.
    #
    secret_store_del "$(get_env_file)" "$profile" "$name" "0644"
    log "🔐 $name stored in profile $profile (backend: $backend)"
  else
    # demoted from a secret: drop the backend item and its reference
    local old_ref
    if old_ref=$(secret_store_get "$(get_secrets_file)" "$profile" "$name")
    then
      secret_backend_del "$old_ref"
      secret_store_del "$(get_secrets_file)" "$profile" "$name" "0600"
    fi
    secret_store_set "$(get_env_file)" "$profile" "$name" "$value" "0644"
    log "📝 $name=$value stored in profile $profile as a plain variable"
    if [ -z "$force" ]
    then
      log "🎓 $name does not look like a credential, so it is kept in clear text in $(get_env_file)"
      log "👉 playground secrets set $name --secret to put it in $(get_secret_backend) instead"
    fi
  fi
}

function secret_delete_value () {
  local name="$1"
  local profile="${2:-$(get_active_secret_profile)}"

  local ref
  if ref=$(secret_store_get "$(get_secrets_file)" "$profile" "$name")
  then
    secret_backend_del "$ref"
    secret_store_del "$(get_secrets_file)" "$profile" "$name" "0600"
    log "🗑️ $name removed from profile $profile"
    return 0
  fi
  if secret_store_get "$(get_env_file)" "$profile" "$name" > /dev/null
  then
    secret_store_del "$(get_env_file)" "$profile" "$name" "0644"
    log "🗑️ $name removed from profile $profile"
    return 0
  fi
  logwarn "🤔 $name is not stored in profile $profile"
  return 1
}

#
# Export into the current process every variable an example needs and that is
# not already set. Scoped to the example's own list, so we never do the
# `set -o allexport; source secrets.properties` trick that leaks every
# credential into every process for the rest of the session.
#
function load_secrets_for_example () {
  local test_file="$1"
  local environment="$2"
  local profile
  profile=$(get_active_secret_profile)
  local loaded=""

  local names
  names=$( { get_mandatory_env_vars "$test_file"; get_optional_env_vars "$test_file" "$environment"; } | sort -u)
  [ -n "$names" ] || return 0

  # one round trip for all of them instead of one per variable
  secret_prefetch "$profile" $names

  local name
  for name in $names
  do
    [ -n "${!name:-}" ] && continue
    local value
    if value=$(secret_get "$name" "$profile")
    then
      export "$name=$value"
      loaded="${loaded} ${name}"
    fi
  done

  if [ -n "$loaded" ]
  then
    log "🔐 Loaded from secrets profile $profile:${loaded}"
  fi
}

#
# Same idea for a CLI command run on its own (`playground connector status` on
# a fully managed connector, ...): export the given variables from the store,
# only into this process and only when they are not already set. This is what
# lets a shell work without `source <(playground secrets env --all)`.
#
function load_secrets_env_vars () {
  local profile
  profile=$(get_active_secret_profile)

  local name missing=""
  for name in "$@"
  do
    [ -n "${!name:-}" ] || missing="${missing} ${name}"
  done
  [ -n "$missing" ] || return 0

  secret_prefetch "$profile" $missing 2> /dev/null

  local value
  for name in $missing
  do
    if value=$(secret_get_from_store "$name" "$profile" 2> /dev/null)
    then
      export "$name=$value"
    fi
  done
  return 0
}
