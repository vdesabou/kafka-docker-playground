user="${args[--user]}"
password="${args[--password]}"
verbose="${args[--verbose]}"
eval "groups=(${args[--group]})"

if [[ -z "$password" ]]
then
  password="$user-secret"
fi

get_environment_used
if [[ "$environment" == "rbac-oauth" ]]
then
  # a Keycloak client with a service account: --user is the client id, --password its secret
  if [[ -n "$(rbac_keycloak_client_uuid "$user")" ]]
  then
    logerror "❌ Keycloak client $user already exists"
    exit 1
  fi
  log "🧑 Adding Keycloak client $user (secret $password)"
  client_uuid=$(rbac_keycloak_client_json "$user" "$password" | rbac_keycloak create clients -r kafka -f - -i) || exit 1
  if [ ${#groups[@]} -gt 0 ]
  then
    sa_user_id=$(rbac_keycloak get "clients/$client_uuid/service-account-user" -r kafka --fields id | jq -r .id) || exit 1
    for group in "${groups[@]}"
    do
      group_id=$(rbac_keycloak get groups -r kafka --fields id,name | jq -r --arg g "$group" '.[] | select(.name == $g) | .id')
      if [[ -z "$group_id" ]]
      then
        log "👥 Creating Keycloak group $group"
        group_id=$(rbac_keycloak create groups -r kafka -s "name=$group" -i) || exit 1
      fi
      log "👥 Adding Keycloak client $user to group $group"
      rbac_keycloak update "users/$sa_user_id/groups/$group_id" -r kafka -s realm=kafka -s "userId=$sa_user_id" -s "groupId=$group_id" -n || exit 1
    done
    log "⏳ the groups claim is in the next token of $user: a client that already has a token sees the change when it gets a new one (accessTokenLifespan of the realm, 1 hour)"
  fi
  log "🔑 Client config: clientId=\"$user\" clientSecret=\"$password\", token endpoint http://keycloak:8080/realms/kafka/protocol/openid-connect/token"
  log "🎓 Give permissions with 'playground rbac role-binding create --principal User:$user ...' or 'playground rbac acl create --principal User:$user ...'"
  exit 0
fi

if [[ -n "$(rbac_ldap ldapsearch -LLL -b "ou=users,$rbac_ldap_base_dn" "uid=$user" dn)" ]]
then
  logerror "❌ user $user already exists"
  exit 1
fi

# next free uidNumber
uid_number=$(rbac_ldap ldapsearch -LLL -b "ou=users,$rbac_ldap_base_dn" "objectClass=posixAccount" uidNumber | awk '/^uidNumber:/ { if ($2 > max) max = $2 } END { print max + 1 }')

log "🧑 Adding user $user (password $password)"
printf '%s\n' \
  "dn: cn=$user,ou=users,$rbac_ldap_base_dn" \
  "objectClass: inetOrgPerson" \
  "objectClass: posixAccount" \
  "objectClass: shadowAccount" \
  "uid: $user" \
  "sn: $user" \
  "givenName: $user" \
  "cn: $user" \
  "displayName: $user" \
  "uidNumber: $uid_number" \
  "gidNumber: 5000" \
  "userPassword: $password" \
  "gecos: $user" \
  "loginShell: /bin/bash" \
  "homeDirectory: /home/$user" | rbac_ldap ldapadd || exit 1

for group in "${groups[@]}"
do
  if [[ -z "$(rbac_ldap ldapsearch -LLL -b "ou=groups,$rbac_ldap_base_dn" "cn=$group" dn)" ]]
  then
    gid_number=$(rbac_ldap ldapsearch -LLL -b "ou=groups,$rbac_ldap_base_dn" "objectClass=posixGroup" gidNumber | awk '/^gidNumber:/ { if ($2 > max) max = $2 } END { print max + 1 }')
    log "👥 Creating group $group"
    printf '%s\n' \
      "dn: cn=$group,ou=groups,$rbac_ldap_base_dn" \
      "objectClass: top" \
      "objectClass: posixGroup" \
      "cn: $group" \
      "gidNumber: $gid_number" | rbac_ldap ldapadd || exit 1
  fi
  log "👥 Adding user $user to group $group"
  # members are cn=<user>,ou=users,... (KAFKA_LDAP_GROUP_MEMBER_ATTRIBUTE_PATTERN)
  printf '%s\n' \
    "dn: cn=$group,ou=groups,$rbac_ldap_base_dn" \
    "changetype: modify" \
    "add: memberUid" \
    "memberUid: cn=$user,ou=users,$rbac_ldap_base_dn" | rbac_ldap ldapmodify || exit 1
done

if [ ${#groups[@]} -gt 0 ]
then
  log "⏳ MDS picks up the group membership within its LDAP refresh interval (60 seconds by default)"
fi
log "🎓 Give permissions with 'playground rbac role-binding create --principal User:$user ...' or 'playground rbac acl create --principal User:$user ...'"
