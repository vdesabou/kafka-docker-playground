user="${args[--user]}"

if [[ ! -n "$user" ]]
then
    user="${USER}"
fi

login_and_maybe_set_azure_subscription

# tmp_dir=$(mktemp -d -t pg-azure-list-XXXXXXXXXX)
# if [ -z "$PG_VERBOSE_MODE" ]
# then
#         trap 'rm -rf $tmp_dir' EXIT
# else
#         log "🐛📂 not deleting tmp dir $tmp_dir"
# fi

# log "🔎 Listing Azure resources tagged with cflt_managed_id=$user and cflt_managed_by=user"

# # Query resources with both tags using strict AND logic
# RES_JSON="$tmp_dir/resources.json"
# az resource list \
#     --query "[?tags.cflt_managed_id=='$user' && tags.cflt_managed_by=='user'].{name:name,type:type,resourceGroup:resourceGroup,location:location,id:id}" \
#     -o json > "$RES_JSON" 2>/dev/null

# if [[ $? -ne 0 ]]; then
#     logerror "Failed to list Azure resources. Ensure you're logged in and have permissions."
#     exit 1
# fi

# count=$(jq -r 'length' "$RES_JSON")
# if [[ "$count" == "0" ]]; then
#     log "No tagged Azure resources found for user $user."
#     exit 0
# fi

# printf "%-20s %-45s %-20s %-10s %-6s\n" "ResourceGroup" "Name" "Type" "Region" "Exists"
# printf "%-20s %-45s %-20s %-10s %-6s\n" "--------------------" "---------------------------------------------" "--------------------" "----------" "------"

# jq -c '.[]' "$RES_JSON" | while read -r item; do
#     rg=$(echo "$item" | jq -r '.resourceGroup')
#     name=$(echo "$item" | jq -r '.name')
#     type=$(echo "$item" | jq -r '.type')
#     loc=$(echo "$item" | jq -r '.location')
#     id=$(echo "$item" | jq -r '.id')

#     # Existence check: try to show the resource
#     if az resource show --ids "$id" >/dev/null 2>&1; then
#         exists="YES"
#     else
#         exists="NO"
#     fi

#     printf "%-20s %-45s %-20s %-10s %-6s\n" "$rg" "$name" "$type" "$loc" "$exists"
# done

for group in $(az group list --query '[].name' --output tsv)
do
    if [[ $group = pg*${user}* ]]
    then
        log "🔥 Azure resource group $group"
        log "Deleting Azure resource group $group"
    fi
done