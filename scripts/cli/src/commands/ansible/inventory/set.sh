path="${args[path]}"
value="${args[value]}"

inventory_file="$root_folder/environment/ansible/inventory/hosts.yml"
before=$(mktemp)
trap 'rm -f "$before"' EXIT
cp "$inventory_file" "$before"
# the value is yaml: numbers, booleans, maps and lists keep their type
log_command yq -i "${path} = $(printf '%s' "$value" | tr '\n' ' ')" environment/ansible/inventory/hosts.yml
if ! VALUE="$value" yq -i -P "${path} = (strenv(VALUE) | from_yaml)" "$inventory_file"
then
  logerror "❌ could not set $path in $inventory_file"
  exit 1
fi
log "✏️ $path = $value"
diff -u "$before" "$inventory_file" | tail -n +3 | grep -E '^[-+]' || log "🤷 no change"
log "🎓 apply it with: playground ansible playbook (--limit <host> for one host)"
