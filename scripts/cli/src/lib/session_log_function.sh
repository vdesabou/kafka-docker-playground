# session log: one line per playground command that changes the environment (a container killed, a fault injected, a
# connector created, records produced...), so that 'playground history --session' and 'playground connector history
# --with-logs' can place them next to the states of the connector and the errors of the logs.
#
# playground-session.log, next to playground.ini (repository root of the CLI that runs, so a worktree has its own):
#   # session started <time> by <command>
#   <start, UTC ISO 8601>\t<start, epoch seconds>\t<duration, seconds>\t<exit code>\t<command line, secrets masked>
# Reset by 'playground start-environment' and 'playground run', kept by 'playground stop' until the next start.

# actions recorded (the $action of bashly): read-only commands never are
SESSION_LOG_ACTIONS=(
  "container recreate" "container update" "container kill-all" "container change-jdk" "container restart"
  "container pause" "container resume" "container kill" "container set-environment-variables"
  "debug block-traffic" "debug degrade-traffic" "debug clock" "debug dns" "debug resources" "debug log-level set"
  "debug enable-remote-debugging" "debug disable-remote-debugging"
  "connector create-or-update" "connector update" "connector delete" "connector pause" "connector resume"
  "connector stop" "connector restart" "connector offsets reset" "connector offsets alter" "connector log-level"
  "connector enable-remote-debugging" "connector disable-remote-debugging"
  "topic produce" "topic create" "topic add-partitions" "topic delete" "topic alter" "topic reassign"
  "topic elect-leader" "topic set-schema-compatibility" "topic dlq replay"
  "quota set" "quota delete"
  "broker config set" "broker config delete" "broker stop" "broker start" "broker rolling-restart"
  "broker transactions abort"
  "schema register" "schema delete" "schema set-compatibility" "schema set-mode" "schema set-normalize"
  "schema import" "schema set-alias" "schema exporter create" "schema exporter pause" "schema exporter resume"
  "schema exporter reset" "schema exporter delete"
  "consumer-group reset-offsets" "consumer-group delete"
  "tcp-proxy start" "tcp-proxy delay" "tcp-proxy break" "tcp-proxy close-connection"
  "tcp-proxy close-all-connection-with-error" "tcp-proxy toggle-accept-connections" "tcp-proxy toggle-reads-client"
  "tcp-proxy toggle-reads-service" "tcp-proxy toggle-writes-client" "tcp-proxy toggle-writes-service"
  "tools http-server set-response" "tools http-server reset"
  "flink cancel"
  "cfk patch" "cfk roll" "cfk upgrade" "cfk operator upgrade" "cfk kraft-migration start"
  "cfk kraft-migration finalize" "cfk kraft-migration release-lock"
  "ansible playbook" "ansible add-host" "ansible upgrade"
  "update-version" "stop"
)

function session_log_file () {
  if [[ -n "$root_folder" ]]
  then
    echo "$root_folder/playground-session.log"
  fi
}

function session_log_is_recorded () {
  local wanted="$1" a
  for a in "${SESSION_LOG_ACTIONS[@]}"
  do
    [[ "$a" == "$wanted" ]] && return 0
  done
  return 1
}

# the command line with the secrets masked: the value of a flag whose name looks like a secret (--password x,
# --password=x), the value of a key=value word whose key does (sasl.jaas.config=..., aws.secret.access.key=...)
function session_log_mask () {
  local secret='(password|passwd|secret|token|credential|jaas|api[._-]?key|access[._-]?key|private[._-]?key|creds)'
  local out=() mask_next="" word
  for word in "$@"
  do
    if [[ -n "$mask_next" ]]
    then
      out+=("********")
      mask_next=""
      continue
    fi
    if [[ "$word" =~ ^--?[A-Za-z0-9._-]*$ ]] && [[ "${word,,}" =~ $secret ]]
    then
      out+=("$word")
      mask_next=1
    elif [[ "$word" == *=* ]] && [[ "${word%%=*}" =~ ^-{0,2}[A-Za-z0-9._-]+$ ]] && [[ "${word%%=*}" =~ $secret ]]
    then
      out+=("${word%%=*}=********")
    else
      out+=("$word")
    fi
  done
  local line="" w
  for w in "${out[@]}"
  do
    if [[ "$w" =~ [[:space:]\"\'\$\`\\\{\}\;\&\|\<\>\(\)] ]] || [[ -z "$w" ]]
    then
      # single quotes, ready to copy and paste: {"id": %g} stays readable
      line+=" '${w//\'/\'\\\'\'}'"
    else
      line+=" $w"
    fi
  done
  echo "${line# }"
}

# truncate the session log at the start of an environment: session_log_reset <command>
function session_log_reset () {
  local file
  file=$(session_log_file)
  [[ -n "$file" ]] || return 0
  { echo "# session started $(date -u +%Y-%m-%dT%H:%M:%SZ) by playground $1"; } > "$file" 2> /dev/null || true
  return 0
}

# append one line: session_log_append <start epoch> <duration> <exit code> <command line>
function session_log_append () {
  local file
  file=$(session_log_file)
  [[ -n "$file" ]] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2> /dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2> /dev/null)" \
    "$1" "$2" "$3" "$4" >> "$file" 2> /dev/null || true
  return 0
}

# called first by the before hook: a recorded command runs again as a child (PG_SESSION_LOG_ACTIVE exported, so that
# neither it nor the playground commands it calls are recorded again), then its line is written with its exit code.
# Running it as a child is what makes the line reliable: a command can exit anywhere and sets its own EXIT trap.
# Never fails because of the log: a log that cannot be written is skipped.
function session_log_wrap () {
  [[ -z "$PG_SESSION_LOG_ACTIVE" ]] || return 0
  [[ -z "$PLAYGROUND_SESSION_LOG_DISABLED" ]] || return 0
  session_log_is_recorded "$action" || return 0
  # 'topic produce --status' only reads the state of the background producers
  if [[ "$action" == "topic produce" ]] && [[ -n "${args[--status]}" ]]
  then
    return 0
  fi
  local file
  file=$(session_log_file)
  [[ -n "$file" ]] || return 0
  if ! touch "$file" 2> /dev/null
  then
    return 0
  fi
  local start=$SECONDS start_epoch rc=0
  start_epoch=$(date +%s)
  PG_SESSION_LOG_ACTIVE=1 "$0" "${input[@]}" || rc=$?
  session_log_append "$start_epoch" "$((SECONDS - start))" "$rc" "$(session_log_mask playground "${input[@]}")"
  exit $rc
}
