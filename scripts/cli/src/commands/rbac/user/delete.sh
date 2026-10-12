user="${args[--user]}"
verbose="${args[--verbose]}"

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
