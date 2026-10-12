file="${args[--file]}"
verbose="${args[--verbose]}"

if [[ -z "$file" ]]
then
  if [[ -z "${args[--principal]}" ]] || [[ -z "${args[--role]}" ]]
  then
    logerror "❌ --principal and --role are required (or --file)"
    exit 1
  fi
  mds_role_binding POST || exit 1
  exit 0
fi

# one role binding per line: <principal> <role> <resource or -> [prefix] [scope=<scope>]
nb=0
line_number=0
while read -r principal role resource options || [[ -n "$principal" ]]
do
  line_number=$((line_number + 1))
  if [[ -z "$principal" ]] || [[ "$principal" == \#* ]]
  then
    continue
  fi
  if [[ -z "$role" ]] || [[ -z "$resource" ]]
  then
    logerror "❌ $file line $line_number: expected <principal> <role> <resource or -> [prefix] [scope=<scope>]"
    exit 1
  fi

  args[--principal]="$principal"
  args[--role]="$role"
  args[--resource]=""
  args[--prefix]=""
  args[--scope]=""
  if [ "$resource" != "-" ]
  then
    args[--resource]="$resource"
  fi
  for option in $options
  do
    case "$option" in
      prefix) args[--prefix]=1 ;;
      scope=*) args[--scope]="${option#scope=}" ;;
      *)
        logerror "❌ $file line $line_number: unknown option $option, it should be prefix or scope=<scope>"
        exit 1
      ;;
    esac
  done

  mds_role_binding POST || exit 1
  nb=$((nb + 1))
done < "$file"

log "✅ $nb role bindings created from $file"
