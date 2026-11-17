to="${args[--to]}"
ansible_cp_version="${args[--ansible-cp-version]}"
parallel="${args[--parallel]}"
no_playbook="${args[--no-playbook]}"

inventory_file="$root_folder/environment/ansible/inventory/hosts.yml"
current=$(yq '.all.vars.confluent_package_version // ""' "$inventory_file")
method=$(yq '.all.vars.installation_method // "package"' "$inventory_file")
log "⬆️ Confluent Platform ${current:-?} -> $to (installation_method: $method)"

if [ "$method" == "archive" ]
then
  ansible_download_archive "$to" || exit 1
  TO="$to" yq -i -P '.all.vars.confluent_archive_file_source = "/cache/confluent-" + strenv(TO) + ".tar.gz" | .all.vars.confluent_archive_file_remote = true' "$inventory_file"
fi
TO="$to" yq -i -P '.all.vars.confluent_package_version = strenv(TO)' "$inventory_file"

# the collection of the same major.minor as the version, as cp-ansible is released with Confluent Platform
if [[ -n "$ansible_cp_version" ]]
then
  spec="==$ansible_cp_version"
else
  major=$(echo "$to" | cut -d "." -f 1)
  minor=$(echo "$to" | cut -d "." -f 2)
  spec=">=${major}.${minor}.0,<${major}.$((minor + 1)).0"
fi
installed=$(docker exec ansible-controller ansible-galaxy collection list confluent.platform 2> /dev/null | awk '$1 == "confluent.platform" {print $2}' | head -1)
log "🅰️ confluent.platform collection: ${installed:-?} -> confluent.platform:$spec"
log_command docker exec ansible-controller ansible-galaxy collection install "confluent.platform:$spec" --force
if ! docker exec ansible-controller ansible-galaxy collection install "confluent.platform:$spec" --force > /tmp/playground-ansible-galaxy.log 2>&1
then
  tail -5 /tmp/playground-ansible-galaxy.log
  logerror "❌ could not install confluent.platform:$spec in ansible-controller"
  exit 1
fi
installed=$(docker exec ansible-controller ansible-galaxy collection list confluent.platform 2> /dev/null | awk '$1 == "confluent.platform" {print $2}' | head -1)
log "🅰️ installed collection: confluent.platform $installed"

if [[ -n "$no_playbook" ]]
then
  log "⏸️ inventory and collection ready, run the playbook with: playground ansible playbook --rolling"
  exit 0
fi

playbook_args=(confluent.platform.all)
if [[ -z "$parallel" ]]
then
  # one host at a time: the procedure of cp-ansible for a running cluster
  playbook_args+=(-e deployment_strategy=rolling)
fi
if ! ansible_run_playbook "${playbook_args[@]}"
then
  exit 1
fi
ansible_handover
if is_container_running connect
then
  playground container wait-for-connect-rest-api-ready --max-wait 300
fi
for host in $(ansible_inventory_hosts)
do
  log "   $host: Confluent Platform $(get_container_cp_tag "$host")"
done
