verbose="${args[--verbose]}"

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
