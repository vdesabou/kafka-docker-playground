verbose="${args[--verbose]}"

get_environment_used
if [[ "$environment" == "ccloud" ]]
then
  ccloud_rbac_acl delete || exit 1
else
  mds_acl remove || exit 1
fi
