principal="${args[--principal]}"
scope="${args[--scope]}"
verbose="${args[--verbose]}"

if [[ -n "$scope" ]]
then
  scopes=("$scope")
else
  scopes=(kafka schema-registry connect ksqldb)
fi

mds_request GET /security/1.0/roles || exit 1
roles=$(jq -r '.[].name' <<< "$mds_output")

rows=""
for scope in "${scopes[@]}"
do
  get_mds_scope "$scope" || exit 1

  if [[ -n "$principal" ]]
  then
    principals=$(normalize_rbac_principal "$principal")
  else
    # every principal having at least one role in this scope
    principals=""
    for role in $roles
    do
      mds_request POST "/security/1.0/lookup/role/$role" "$mds_scope" || exit 1
      principals="$principals $(jq -r '.[]' <<< "$mds_output")"
    done
    principals=$(tr ' ' '\n' <<< "$principals" | grep -v '^$' | sort -u)
  fi

  for p in $principals
  do
    mds_request POST "/security/1.0/lookup/rolebindings/principal/$p" "$mds_scope" || exit 1
    rows="$rows$(jq -r --arg scope "$scope" '
      .rolebindings // {} | to_entries[] | .key as $principal | .value | to_entries[] | .key as $role |
      if (.value | length) == 0
      then [$principal, $role, $scope, "(cluster)"]
      else .value[] | [$principal, $role, $scope, "\(.resourceType):\(.name)" + (if .patternType == "PREFIXED" then " (prefixed)" else "" end)]
      end | @tsv' <<< "$mds_output")"$'\n'
  done
done

rows=$(grep -v '^$' <<< "$rows" || true)
if [[ -z "$rows" ]]
then
  logwarn "no role binding found"
  exit 0
fi

{
  printf "PRINCIPAL\tROLE\tSCOPE\tRESOURCE\n"
  echo "$rows"
} | column -t -s $'\t'
