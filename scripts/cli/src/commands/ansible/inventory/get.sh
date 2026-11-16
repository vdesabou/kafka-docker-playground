path="${args[path]}"

inventory_file="$root_folder/environment/ansible/inventory/hosts.yml"
yq "${path:-.}" "$inventory_file"
