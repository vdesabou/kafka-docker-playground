verbose="${args[--verbose]}"

get_environment_used
if [[ "$environment" == "ccloud" ]]
then
  ccloud_rbac_acl create || exit 1
else
  mds_acl add || exit 1
fi
