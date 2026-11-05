verbose="${args[--verbose]}"

get_environment_used
if [[ "$environment" == "rbac-oauth" ]]
then
  # users are the Keycloak clients with a service account (client_credentials grant), groups are Keycloak groups
  clients=$(rbac_keycloak get clients -r kafka --fields clientId,secret,serviceAccountsEnabled) || exit 1
  keycloak_groups=$(rbac_keycloak get groups -r kafka --fields id,name) || exit 1
  memberships=""
  while IFS=$'\t' read -r group_id group_name
  do
    [[ -z "$group_id" ]] && continue
    members=$(rbac_keycloak get "groups/$group_id/members" -r kafka --fields username) || exit 1
    memberships="$memberships$(jq -r --arg g "$group_name" '.[] | .username + "\t" + $g' <<< "$members")"$'\n'
  done < <(jq -r '.[] | .id + "\t" + .name' <<< "$keycloak_groups")
  {
    printf "CLIENT ID\tCLIENT SECRET\tGROUPS\n"
    jq -r '.[] | select(.serviceAccountsEnabled == true) | .clientId + "\t" + (.secret // "-")' <<< "$clients" | while IFS=$'\t' read -r client_id client_secret
    do
      user_groups=$(awk -F'\t' -v u="service-account-$(tr '[:upper:]' '[:lower:]' <<< "$client_id")" '$1 == u { printf "%s%s", sep, $2; sep = "," }' <<< "$memberships")
      printf "%s\t%s\t%s\n" "$client_id" "$client_secret" "${user_groups:--}"
    done | sort -f
  } | column -t -s $'\t'
  exit 0
fi

users=$(rbac_ldap ldapsearch -LLL -b "ou=users,$rbac_ldap_base_dn" "objectClass=inetOrgPerson" uid userPassword) || exit 1
groups=$(rbac_ldap ldapsearch -LLL -b "ou=groups,$rbac_ldap_base_dn" "objectClass=posixGroup" cn memberUid) || exit 1

rows=""
user=""
while read -r key value
do
  case "$key" in
    uid:)
      user="$value"
    ;;
    userPassword:|userPassword::)
      password="$value"
      if [ "$key" == "userPassword::" ]
      then
        # base64 encoded
        password=$(base64 -d <<< "$value" 2> /dev/null || base64 -D <<< "$value")
      fi
      user_groups=$(awk -v member="cn=$user,ou=users,$rbac_ldap_base_dn" '/^cn:/ { group = $2 } /^memberUid:/ && $2 == member { printf "%s%s", sep, group; sep = "," }' <<< "$groups")
      rows="$rows$user"$'\t'"$password"$'\t'"${user_groups:--}"$'\n'
    ;;
  esac
done <<< "$users"

{
  printf "USER\tPASSWORD\tGROUPS\n"
  printf "%s" "$rows" | sort -f
} | column -t -s $'\t'
