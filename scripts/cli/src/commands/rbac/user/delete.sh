user="${args[--user]}"
verbose="${args[--verbose]}"

get_environment_used
if [[ "$environment" == "rbac-oauth" ]]
then
  client_uuid=$(rbac_keycloak_client_uuid "$user")
  if [[ -z "$client_uuid" ]]
  then
    logerror "❌ Keycloak client $user does not exist"
    exit 1
  fi
  log "🗑️ Deleting Keycloak client $user (and its service account)"
  rbac_keycloak delete "clients/$client_uuid" -r kafka || exit 1
  logwarn "role bindings and ACLs of User:$user are not deleted, see 'playground rbac role-binding list --principal User:$user' and 'playground rbac acl list --principal User:$user'. A token it already has stays valid until it expires"
  exit 0
fi

if [[ -z "$(rbac_ldap ldapsearch -LLL -b "ou=users,$rbac_ldap_base_dn" "uid=$user" dn)" ]]
then
  logerror "❌ user $user does not exist"
  exit 1
fi

member="cn=$user,ou=users,$rbac_ldap_base_dn"
for group in $(rbac_ldap ldapsearch -LLL -b "ou=groups,$rbac_ldap_base_dn" "memberUid=$member" cn | awk '/^cn:/ { print $2 }')
do
  log "👥 Removing user $user from group $group"
  printf '%s\n' \
    "dn: cn=$group,ou=groups,$rbac_ldap_base_dn" \
    "changetype: modify" \
    "delete: memberUid" \
    "memberUid: $member" | rbac_ldap ldapmodify || exit 1
done

log "🗑️ Deleting user $user"
rbac_ldap ldapdelete "$member" || exit 1
logwarn "role bindings and ACLs of User:$user are not deleted, see 'playground rbac role-binding list --principal User:$user' and 'playground rbac acl list --principal User:$user'"
