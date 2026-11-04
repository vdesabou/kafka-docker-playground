# playground flink sql|list-jobs|cancel on Confluent Cloud: the statements of a Flink compute pool, managed with the
# confluent CLI. The rows of a query (SELECT, SHOW, DESCRIBE…) are not printed by 'confluent flink statement create':
# they are read with the statement results REST API, authenticated with a Flink API key (see get_ccloud_flink_api_key).

# local (the jobmanager of --enable-flink) or ccloud: --environment, else PLAYGROUND_FLINK_ENVIRONMENT, else ccloud
# when the last example ran on Confluent Cloud. Sets $flink_environment.
function get_flink_environment () {
  flink_environment="${args[--environment]}"
  flink_environment=${flink_environment:-$PLAYGROUND_FLINK_ENVIRONMENT}
  if [[ -z "$flink_environment" ]]
  then
    if [[ "$(playground state get run.environment 2>/dev/null)" == "ccloud" ]]
    then
      flink_environment="ccloud"
    else
      flink_environment="local"
    fi
  fi
  # the nested playground calls (get-flink-job-list, list-jobs) use the same one
  export PLAYGROUND_FLINK_ENVIRONMENT="$flink_environment"
}

# prefix of the statements created by 'playground flink sql': 'flink cancel --all' only stops those, the compute
# pool can be shared with other users
function get_ccloud_flink_statement_prefix () {
  local user
  user=$(echo "${USER:-playground}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-' | cut -c1-20)
  ccloud_flink_statement_prefix="pg-${user}-"
}

# the Confluent Cloud environment, cloud, region and Kafka cluster of the last ccloud example
# (playground.ini [ccloud], or ENVIRONMENT, CLUSTER_NAME, CLUSTER_CLOUD and CLUSTER_REGION), and the compute pool:
# FLINK_COMPUTE_POOL, else the one stored by the example (ccloud.FLINK_COMPUTE_POOL), else the first provisioned
# pool of the environment in the region of the cluster.
# Sets ccloud_flink_env, ccloud_flink_cloud, ccloud_flink_region, ccloud_flink_cluster_name, ccloud_flink_cluster_id,
# ccloud_flink_compute_pool and ccloud_flink_location_flags (an array: --environment --cloud --region).
function get_ccloud_flink_context () {
  if [[ $(type confluent 2>&1) =~ "not found" ]]
  then
    logerror "❌ the confluent CLI is required for Confluent Cloud Flink statements: https://docs.confluent.io/confluent-cli/current/install.html"
    return 1
  fi
  ccloud_flink_env=$(playground state get ccloud.ENVIRONMENT 2>/dev/null)
  ccloud_flink_env=${ccloud_flink_env:-$ENVIRONMENT}
  ccloud_flink_cluster_name=$(playground state get ccloud.CLUSTER_NAME 2>/dev/null)
  ccloud_flink_cluster_name=${ccloud_flink_cluster_name:-$CLUSTER_NAME}
  ccloud_flink_cloud=$(playground state get ccloud.CLUSTER_CLOUD 2>/dev/null)
  ccloud_flink_cloud=$(echo "${ccloud_flink_cloud:-$CLUSTER_CLOUD}" | tr '[:upper:]' '[:lower:]')
  ccloud_flink_region=$(playground state get ccloud.CLUSTER_REGION 2>/dev/null)
  ccloud_flink_region=${ccloud_flink_region:-$CLUSTER_REGION}

  if [[ -z "$ccloud_flink_env" ]] || [[ -z "$ccloud_flink_cloud" ]] || [[ -z "$ccloud_flink_region" ]]
  then
    logerror "❌ no Confluent Cloud environment: run a ccloud example first (ccloud/flink-sql-kafka), or set ENVIRONMENT, CLUSTER_NAME, CLUSTER_CLOUD and CLUSTER_REGION"
    return 1
  fi
  ccloud_flink_location_flags=(--environment "$ccloud_flink_env" --cloud "$ccloud_flink_cloud" --region "$ccloud_flink_region")

  local clusters
  if ! clusters=$(confluent kafka cluster list --environment "$ccloud_flink_env" -o json 2>&1)
  then
    if echo "$clusters" | grep -q -e "You must login" -e "session has expired"
    then
      logerror "❌ the confluent CLI is not logged in: run 'confluent login' and try again"
    else
      logerror "❌ could not list the Kafka clusters of environment $ccloud_flink_env: $clusters"
    fi
    return 1
  fi
  ccloud_flink_cluster_id=""
  if [[ -n "$ccloud_flink_cluster_name" ]]
  then
    ccloud_flink_cluster_id=$(echo "$clusters" | jq -r --arg name "$ccloud_flink_cluster_name" '[.[] | select(.name == $name)][0].id // empty' 2>/dev/null)
  fi

  ccloud_flink_compute_pool="${FLINK_COMPUTE_POOL}"
  if [[ -z "$ccloud_flink_compute_pool" ]]
  then
    ccloud_flink_compute_pool=$(playground state get ccloud.FLINK_COMPUTE_POOL 2>/dev/null)
  fi
  local pools
  pools=$(confluent flink compute-pool list --environment "$ccloud_flink_env" -o json 2>/dev/null)
  if [[ -n "$ccloud_flink_compute_pool" ]] && ! echo "$pools" | jq -e --arg id "$ccloud_flink_compute_pool" 'any(.[]; .id == $id)' > /dev/null 2>&1
  then
    logwarn "compute pool $ccloud_flink_compute_pool is not in environment $ccloud_flink_env, looking for another one"
    ccloud_flink_compute_pool=""
  fi
  if [[ -z "$ccloud_flink_compute_pool" ]]
  then
    ccloud_flink_compute_pool=$(echo "$pools" | jq -r --arg cloud "$ccloud_flink_cloud" --arg region "$ccloud_flink_region" \
      '[.[] | select((.cloud | ascii_downcase) == $cloud and .region == $region and .status == "PROVISIONED")][0].id // empty' 2>/dev/null)
  fi
  if [[ -z "$ccloud_flink_compute_pool" ]]
  then
    logerror "❌ no Flink compute pool in environment $ccloud_flink_env for $ccloud_flink_cloud $ccloud_flink_region: run ccloud/flink-sql-kafka, or create one with:"
    logerror "   confluent flink compute-pool create kdp-flink-$ccloud_flink_cloud-$ccloud_flink_region --cloud $ccloud_flink_cloud --region $ccloud_flink_region --max-cfu 10 --environment $ccloud_flink_env"
    return 1
  fi
}

# organization id and Flink API key of the region, to read the statement results with the REST API: FLINK_API_KEY and
# FLINK_API_SECRET when exported, else the key kept in the playground secrets store (playground secrets, outside the
# repository: keychain, 1Password… see playground secrets backend) for this environment and region, else a new key owned
# by the logged in user, stored there and reused by the next calls. Sets ccloud_flink_rest_url and ccloud_flink_rest_auth.
function get_ccloud_flink_api_key () {
  local org key secret scope
  # not cached: the CLI can be logged in to another organization since the last call
  org=$(confluent organization describe -o json 2>/dev/null | jq -r '.id // empty')
  if [[ -z "$org" ]]
  then
    logerror "❌ could not get the organization id with confluent organization describe"
    return 1
  fi
  ccloud_flink_rest_url="https://flink.${ccloud_flink_region}.${ccloud_flink_cloud}.confluent.cloud/sql/v1/organizations/${org}/environments/${ccloud_flink_env}"

  scope="$org/$ccloud_flink_env/$ccloud_flink_cloud/$ccloud_flink_region"
  key="$FLINK_API_KEY"
  secret="$FLINK_API_SECRET"
  if [[ -z "$key" ]] || [[ -z "$secret" ]]
  then
    key=""
    secret=""
    if [[ "$(secret_get_from_store FLINK_API_KEY_SCOPE 2>/dev/null)" == "$scope" ]]
    then
      key=$(secret_get_from_store FLINK_API_KEY 2>/dev/null)
      secret=$(secret_get_from_store FLINK_API_SECRET 2>/dev/null)
    fi
  fi
  if [[ -z "$key" ]] || [[ -z "$secret" ]]
  then
    log "🔑 creating a Flink API key for $ccloud_flink_cloud $ccloud_flink_region (environment $ccloud_flink_env), to read the results of the queries" >&2
    local created
    created=$(confluent api-key create --resource flink "${ccloud_flink_location_flags[@]}" --description "kafka-docker-playground playground flink sql (${USER})" -o json 2>/dev/null)
    key=$(echo "$created" | jq -r '.api_key // empty' 2>/dev/null)
    secret=$(echo "$created" | jq -r '.api_secret // empty' 2>/dev/null)
    if [[ -z "$key" ]] || [[ -z "$secret" ]]
    then
      logerror "❌ could not create a Flink API key, set FLINK_API_KEY and FLINK_API_SECRET"
      return 1
    fi
    {
      # stdin is the stream of statements of flink_ccloud_sql: a 1Password CLI reading it would fail
      secret_store_value FLINK_API_KEY "$key" "" secret &&
      secret_store_value FLINK_API_SECRET "$secret" "" secret &&
      secret_store_value FLINK_API_KEY_SCOPE "$scope" "" plain
    } < /dev/null >&2 || logwarn "could not store the Flink API key in the playground secrets store, it is only used by this call" >&2
  fi
  ccloud_flink_rest_auth="$key:$secret"
}

# GET on the Flink REST API, retried while a new API key is not yet active (401, a few seconds after its creation)
function ccloud_flink_rest_get () {
  local url="$1" i code out
  out=$(mktemp)
  for i in {1..30}
  do
    code=$(curl -s -o "$out" -w "%{http_code}" -u "$ccloud_flink_rest_auth" "$url")
    if [[ "$code" != "401" ]]
    then
      break
    fi
    sleep 2
  done
  cat "$out"
  rm -f "$out"
  [[ "$code" == "200" ]]
}

# split SQL on the ; outside of quotes, backticks and comments: one statement per NUL terminated record, trimmed
function split_flink_sql_statements () {
  perl -0777 -ne '
    my ($cur, $q) = ("", "");
    my @c = split //, $_;
    for (my $i = 0; $i < @c; $i++) {
      my $ch = $c[$i];
      if ($q eq "--") { if ($ch eq "\n") { $q = ""; $cur .= $ch; } next; }
      if ($q eq "/*") { if ($ch eq "*" && $i + 1 < @c && $c[$i+1] eq "/") { $q = ""; $i++; } next; }
      if ($q ne "") { $cur .= $ch; $q = "" if $ch eq $q; next; }
      if ($ch eq "-" && $i + 1 < @c && $c[$i+1] eq "-") { $q = "--"; $i++; next; }
      if ($ch eq "/" && $i + 1 < @c && $c[$i+1] eq "*" && !($i + 2 < @c && $c[$i+2] eq "+")) { $q = "/*"; $i++; next; }
      if ($ch eq "\x27" || $ch eq "`" || $ch eq "\"") { $q = $ch; $cur .= $ch; next; }
      if ($ch eq ";") { $cur =~ s/^\s+|\s+$//g; print "$cur\0" if length $cur; $cur = ""; next; }
      $cur .= $ch;
    }
    $cur =~ s/^\s+|\s+$//g; print "$cur\0" if length $cur;
  '
}

# print the rows of a query as a table, like the tableau result mode of the Flink SQL client. The changelog
# (+I -U +U -D) is applied, so an aggregation prints its final value, like the table mode of 'confluent flink shell'.
# $1: statement json (REST API), $2: file with one {op,row} json per line
function print_ccloud_flink_rows () {
  local statement="$1" rows_file="$2"
  jq -r -n --argjson st "$statement" --slurpfile changes "$rows_file" '
    def cell: if . == null then "<NULL>" elif type == "string" then gsub("[\t\n\r]"; " ") else tojson end;
    ($st.status.traits.schema.columns // [] | map(.name)) as $cols
    | ($st.status.traits.upsert_columns // null) as $keys
    | def key($r): if $keys == null then $r else [$keys[] as $k | $r[$k]] end;
    # ops: 0 +I, 1 -U, 2 +U, 3 -D. Upsert results (upsert_columns) replace or delete the row with the same key,
    # retract results remove the same row
      (reduce $changes[] as $c ([];
        (key($c.row)) as $k
        | ([to_entries[] | select(key(.value) == $k) | .key][0]) as $i
        | if ($c.op == 1 or $c.op == 3) then (if $i == null then . else del(.[$i]) end)
          elif ($keys != null and $i != null) then .[$i] = $c.row
          else . + [$c.row] end)) as $rows
    | ($cols | @tsv), ($rows[0:200][] | map(cell) | @tsv), (if ($rows | length) > 200 then "@@TOTAL@@\($rows | length)" else empty end)
  ' | awk -F'\t' '
    /^@@TOTAL@@/ { total = substr($0, 10); next }
    { n++; for (i = 1; i <= NF; i++) { v[n, i] = $i; if (length($i) > w[i]) w[i] = length($i); if (NF > maxf) maxf = NF } }
    function sep(   i, s) { s = "+"; for (i = 1; i <= maxf; i++) { s = s sprintf("%s+", dashes(w[i] + 2)) } print s }
    function dashes(k,   s) { s = ""; while (k-- > 0) s = s "-"; return s }
    function line(r,   i, s) { s = "|"; for (i = 1; i <= maxf; i++) { s = s sprintf(" %" w[i] "s |", v[r, i]) } print s }
    END {
      if (n == 0) exit
      sep(); line(1); sep()
      for (r = 2; r <= n; r++) line(r)
      if (n > 1) sep()
      if (total != "") printf "%d rows in set, only the first %d are printed: add a LIMIT\n", total, n - 1
      else printf "%d row%s in set\n", n - 1, (n - 1 == 1 ? "" : "s")
    }'
}

function flink_ccloud_sql () {
  local sql="$1" max_wait="$2"
  get_ccloud_flink_context || exit 1
  get_ccloud_flink_statement_prefix

  local catalog_name
  catalog_name=$(confluent environment describe "$ccloud_flink_env" -o json 2>/dev/null | jq -r '.name // empty')
  log "🐿️ Running Flink SQL statements on Confluent Cloud (compute pool $ccloud_flink_compute_pool, $ccloud_flink_cloud $ccloud_flink_region, catalog ${catalog_name:-$ccloud_flink_env}, database ${ccloud_flink_cluster_name:-none})"

  local tmp_dir
  tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
  trap 'rm -rf $tmp_dir' EXIT

  declare -A properties=()
  local stmt n=0 failed=0 timed_out=0 run_id
  run_id=$(date +%Y%m%d%H%M%S)
  while IFS= read -r -d '' stmt
  do
    local one_line
    one_line=$(printf "%s" "$stmt" | tr '\n' ' ' | sed 's/  */ /g')
    echo "Flink SQL> $one_line"

    # client side statements of the Flink shell: sent as properties of the next statements
    local keyword
    keyword=$(printf '%s' "$stmt" | sed -E 's/^[[:space:](]*//' | awk 'NR == 1 {print tolower($1)}')
    case "$keyword" in
      set)
        local kv
        kv=$(printf '%s' "$stmt" | perl -0777 -ne 'print "$1\t$2" if /^\s*set\s+[\x27"]([^\x27"]+)[\x27"]\s*=\s*[\x27"](.*)[\x27"]\s*$/is')
        if [[ -z "$kv" ]]
        then
          echo "[ERROR] expected SET 'key' = 'value'"
          failed=1
          break
        fi
        properties["${kv%%$'\t'*}"]="${kv#*$'\t'}"
        echo "[INFO] Execute statement succeeded (property ${kv%%$'\t'*} of the next statements)."
        continue
        ;;
      reset)
        properties=()
        echo "[INFO] Execute statement succeeded."
        continue
        ;;
      use)
        local target
        target=$(printf '%s' "$stmt" | perl -0777 -ne 'my ($k, $v); if (/^\s*use\s+catalog\s+(.+?)\s*$/is) { ($k, $v) = ("sql.current-catalog", $1) } elsif (/^\s*use\s+(.+?)\s*$/is) { ($k, $v) = ("sql.current-database", $1) } $v =~ s/^[`"]|[`"]$//g; print "$k\t$v"')
        properties["${target%%$'\t'*}"]="${target#*$'\t'}"
        echo "[INFO] Execute statement succeeded."
        continue
        ;;
    esac

    n=$((n+1))
    local name="${ccloud_flink_statement_prefix}${run_id}-${n}"
    local create_flags=(--compute-pool "$ccloud_flink_compute_pool" "${ccloud_flink_location_flags[@]}" --wait -o json)
    if [[ -z "${properties[sql.current-database]}" ]] && [[ -n "$ccloud_flink_cluster_id" ]]
    then
      create_flags+=(--database "$ccloud_flink_cluster_id")
    fi
    local k
    for k in "${!properties[@]}"
    do
      create_flags+=(--property "$k=${properties[$k]}")
    done

    local created status
    created=$(confluent flink statement create "$name" --sql "$stmt" "${create_flags[@]}" 2> "$tmp_dir/stderr")
    status=$(echo "$created" | jq -r '.status // empty' 2>/dev/null)
    if [[ -z "$status" ]]
    then
      echo "[ERROR] $(grep -v "No Flink endpoint is specified" "$tmp_dir/stderr")"
      failed=1
      break
    fi
    # --wait returns once RUNNING: a DDL (CREATE, DROP, ALTER…) completes a few seconds later, wait for it so that the
    # next statements see its table. Not a CREATE TABLE … AS SELECT, a statement that keeps running like an INSERT
    if [[ "$status" == "RUNNING" || "$status" == "PENDING" ]] && [[ "$keyword" =~ ^(create|drop|alter|truncate)$ ]] \
       && ! printf '%s' "$stmt" | perl -0777 -ne 'exit(/\bas\s+[(\s]*(select|with|values)\b/i ? 0 : 1)'
    then
      local wait_start=$SECONDS
      while [[ "$status" == "RUNNING" || "$status" == "PENDING" ]] && [ $((SECONDS - wait_start)) -lt "$max_wait" ]
      do
        sleep 1
        created=$(confluent flink statement describe "$name" "${ccloud_flink_location_flags[@]}" -o json 2>/dev/null)
        status=$(echo "$created" | jq -r '.status // empty' 2>/dev/null)
      done
    fi
    if [[ "$status" == "FAILED" ]] || [[ "$status" == "FAILING" ]]
    then
      echo "[ERROR] $(echo "$created" | jq -r '.status_detail // "statement failed"')"
      confluent flink statement delete "$name" --force "${ccloud_flink_location_flags[@]}" > /dev/null 2>&1
      failed=1
      break
    fi

    local is_query=0
    case "$keyword" in
      select|with|show|describe|desc|explain|values) is_query=1 ;;
    esac

    if [ $is_query -eq 0 ]
    then
      if [[ "$status" == "COMPLETED" ]]
      then
        echo "[INFO] Execute statement succeeded."
        confluent flink statement delete "$name" --force "${ccloud_flink_location_flags[@]}" > /dev/null 2>&1
      else
        echo "[INFO] Statement $name is $status on compute pool $ccloud_flink_compute_pool"
        log "🚀 Statement $name submitted, follow it with: playground flink list-jobs"
      fi
      continue
    fi

    # a query: read its rows with the statement results REST API until it is COMPLETED, or --max-wait
    get_ccloud_flink_api_key || exit 1
    local statement phase next start truncated=0 rows_file="$tmp_dir/rows-$n.jsonl"
    : > "$rows_file"
    # a LIMIT on an unbounded table keeps the statement RUNNING once its rows are produced: stop reading then
    local limit
    limit=$(printf '%s' "$stmt" | perl -0777 -ne 'print $1 if /\blimit\s+(\d+)\s*$/i')
    start=$SECONDS
    next="${ccloud_flink_rest_url}/statements/${name}/results"
    statement=""
    while true
    do
      statement=$(ccloud_flink_rest_get "${ccloud_flink_rest_url}/statements/${name}") || statement=""
      phase=$(echo "$statement" | jq -r '.status.phase // empty' 2>/dev/null)
      if [[ "$phase" == "FAILED" ]] || [[ "$phase" == "FAILING" ]]
      then
        echo "[ERROR] $(echo "$statement" | jq -r '.status.detail // "statement failed"')"
        failed=1
        break
      fi
      local page page_next nb_rows=0
      # a page without 'next' is the last one only when the statement was already COMPLETED before the call (the
      # phase is read first). Otherwise the same page is read again later: its rows are only kept then
      if page=$(ccloud_flink_rest_get "$next")
      then
        page_next=$(echo "$page" | jq -r '.metadata.next // empty' 2>/dev/null)
        if [[ -n "$page_next" ]] || [[ "$phase" == "COMPLETED" ]]
        then
          echo "$page" | jq -c '.results.data[]? | {op: (.op // 0), row: .row}' >> "$rows_file"
          nb_rows=$(echo "$page" | jq '.results.data // [] | length' 2>/dev/null)
        fi
        if [[ -n "$page_next" ]]
        then
          next="$page_next"
        elif [[ "$phase" == "COMPLETED" ]]
        then
          break
        fi
        if [[ -n "$limit" ]] && [ "$(wc -l < "$rows_file" | tr -d ' ')" -ge "$limit" ]
        then
          break
        fi
      fi
      if [ $((SECONDS - start)) -ge "$max_wait" ]
      then
        timed_out=1
        break
      fi
      if [ "$(wc -l < "$rows_file" | tr -d ' ')" -ge 10000 ]
      then
        truncated=1
        break
      fi
      if [[ "$nb_rows" == "0" ]]
      then
        sleep 1
      fi
    done
    if [[ -n "$statement" ]] && [ "$(wc -l < "$rows_file" | tr -d ' ')" != "0" ]
    then
      print_ccloud_flink_rows "$statement" "$rows_file"
    elif [ $failed -eq 0 ]
    then
      echo "Empty set"
    fi
    if [ $truncated -eq 1 ]
    then
      logwarn "✂️ stopped reading the results after 10000 changes: add a LIMIT"
    fi
    # the results of a query are only readable while the statement exists: delete it once read (stops it when running)
    confluent flink statement delete "$name" --force "${ccloud_flink_location_flags[@]}" > /dev/null 2>&1
    if [ $failed -eq 1 ] || [ $timed_out -eq 1 ]
    then
      break
    fi
  done < <(printf '%s' "$sql" | split_flink_sql_statements)

  if [ $failed -eq 1 ]
  then
    logerror "❌ a Flink SQL statement failed, the next statements were not run"
    exit 1
  fi
  if [ $timed_out -eq 1 ]
  then
    logwarn "⏱️ the query was stopped and deleted after ${max_wait}s: a SELECT on an unbounded table never ends in streaming mode"
    logwarn "   add a LIMIT, read a bounded range with /*+ OPTIONS('scan.bounded.mode'='latest-offset') */, or increase --max-wait"
    exit 1
  fi
}

# statements of the compute pool, most recent first (the 'confluent flink statement list' json)
function get_ccloud_flink_statements () {
  local state="$1"
  confluent flink statement list --compute-pool "$ccloud_flink_compute_pool" "${ccloud_flink_location_flags[@]}" -o json 2>/dev/null \
    | jq --arg state "$state" '[.[] | select($state == "" or .status == $state)] | sort_by(.creation_date) | reverse'
}

function flink_ccloud_list_jobs () {
  local state="$1" json="$2"
  get_ccloud_flink_context || exit 1
  local statements
  statements=$(get_ccloud_flink_statements "$state")
  if [[ -z "$statements" ]]
  then
    logerror "❌ could not list the statements of compute pool $ccloud_flink_compute_pool"
    exit 1
  fi
  if [[ -n "$json" ]]
  then
    echo "$statements"
    exit 0
  fi

  log "📋 Statements of Flink compute pool $ccloud_flink_compute_pool on Confluent Cloud ($ccloud_flink_cloud $ccloud_flink_region, environment $ccloud_flink_env)"
  if [ "$(echo "$statements" | jq 'length')" == "0" ]
  then
    if [[ -n "$state" ]]
    then
      log "🤷 no statement in status $state"
    else
      log "🤷 no statement, submit one with playground flink sql"
    fi
    exit 0
  fi

  {
    printf 'STATEMENT NAME\tSTATUS\tSQL\tCREATED\tAGE\n'
    echo "$statements" | jq -r --argjson now "$(date +%s)" '.[] |
        (.creation_date | sub("\\.[0-9]+"; "") | fromdateiso8601) as $created |
        ($now - $created) as $s |
        [.name, .status, (.statement | gsub("\\s+"; " ") | if length > 60 then .[0:57] + "..." else . end),
         ($created | localtime | strftime("%Y-%m-%d %H:%M:%S")),
         (if $s >= 86400 then "\($s / 86400 | floor)d\($s % 86400 / 3600 | floor)h"
          elif $s >= 3600 then "\($s / 3600 | floor)h\($s % 3600 / 60 | floor)m"
          elif $s >= 60 then "\($s / 60 | floor)m\($s % 60)s"
          else "\($s)s" end)] | @tsv'
  } | column -t -s $'\t'

  local name
  for name in $(echo "$statements" | jq -r '[.[] | select(.status == "FAILED" or .status == "DEGRADED")][0:5][] | .name')
  do
    local detail
    detail=$(confluent flink statement describe "$name" "${ccloud_flink_location_flags[@]}" -o json 2>/dev/null | jq -r '.status_detail // empty')
    if [[ -z "$detail" ]]
    then
      detail=$(confluent flink statement exception list "$name" "${ccloud_flink_location_flags[@]}" -o json 2>/dev/null | jq -r '.[0].message // empty' 2>/dev/null)
    fi
    if [[ -n "$detail" ]]
    then
      logerror "❌ statement $name:"
      echo "$detail" | head -5
    fi
  done
  if echo "$statements" | jq -e 'any(.[]; .status == "FAILED" or .status == "DEGRADED")' > /dev/null
  then
    log "🎓 all the exceptions of a statement: confluent flink statement exception list <statement name> ${ccloud_flink_location_flags[*]}"
  fi
}

function flink_ccloud_cancel () {
  local job="$1" all="$2" delete="$3"
  get_ccloud_flink_context || exit 1
  get_ccloud_flink_statement_prefix
  local names running
  # without --job, only the statements created by 'playground flink sql' of this user: the pool can be shared
  # with --delete, whatever their status (a STOPPED statement stays in the pool until it is deleted)
  local status_filter="RUNNING"
  if [[ -n "$delete" ]]
  then
    status_filter=""
  fi
  running=$(get_ccloud_flink_statements "$status_filter" | jq -r --arg p "$ccloud_flink_statement_prefix" '.[] | select(.name | startswith($p)) | select(.status != "DELETING") | .name')
  if [[ -n "$job" ]]
  then
    names="$job"
  elif [[ -z "$running" ]]
  then
    log "🤷 no ${status_filter:+running }statement created by playground flink sql (prefix $ccloud_flink_statement_prefix) to $([[ -n "$delete" ]] && echo delete || echo cancel)"
    exit 0
  elif [[ -n "$all" ]] || [ "$(echo "$running" | wc -l | tr -d ' ')" == "1" ]
  then
    names="$running"
  else
    logerror "❌ several statements are running, choose one with --job, or cancel them all with --all:"
    playground flink list-jobs --environment ccloud --state RUNNING
    exit 1
  fi

  local failed=0 name
  for name in $names
  do
    local status
    status=$(confluent flink statement describe "$name" "${ccloud_flink_location_flags[@]}" -o json 2>/dev/null | jq -r '.status // empty')
    if [[ -z "$status" ]]
    then
      logerror "❌ statement $name does not exist, see playground flink list-jobs"
      failed=1
      continue
    fi
    if [[ -n "$delete" ]]
    then
      log "🗑️ Deleting statement $name ($status)"
      if confluent flink statement delete "$name" --force "${ccloud_flink_location_flags[@]}" > /dev/null 2>&1
      then
        log "✅ Statement $name is deleted"
      else
        logerror "❌ could not delete statement $name"
        failed=1
      fi
      continue
    fi
    if [[ "$status" != "STOPPED" ]] && [[ "$status" != "COMPLETED" ]] && [[ "$status" != "FAILED" ]]
    then
      log "🛑 Stopping statement $name ($status)"
      if ! confluent flink statement stop "$name" "${ccloud_flink_location_flags[@]}" > /dev/null 2>&1
      then
        logerror "❌ could not stop statement $name"
        failed=1
        continue
      fi
    fi
    local i
    for i in {1..60}
    do
      status=$(confluent flink statement describe "$name" "${ccloud_flink_location_flags[@]}" -o json 2>/dev/null | jq -r '.status // empty')
      if [[ "$status" == "STOPPED" ]] || [[ "$status" == "COMPLETED" ]] || [[ "$status" == "FAILED" ]]
      then
        break
      fi
      sleep 1
    done
    if [[ "$status" == "STOPPED" ]] || [[ "$status" == "COMPLETED" ]]
    then
      log "✅ Statement $name is $status (resume it with confluent flink statement resume $name, delete it with playground flink cancel --job $name --delete)"
    else
      logerror "❌ statement $name is $status after 60 seconds"
      failed=1
    fi
  done
  exit $failed
}
