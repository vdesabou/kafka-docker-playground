path="${args[path]}"

inventory_file="$root_folder/environment/ansible/inventory/hosts.yml"
before=$(mktemp)
trap 'rm -f "$before"' EXIT
cp "$inventory_file" "$before"
if ! yq -i -P "del(${path})" "$inventory_file"
then
  logerror "❌ could not delete $path in $inventory_file"
  exit 1
fi
log "🗑️ $path removed"
diff -u "$before" "$inventory_file" | tail -n +3 | grep -E '^[-+]' || log "🤷 no change, $path was not set"
log "🎓 apply it with: playground ansible playbook (--limit <host> for one host)"
