limit="${args[--limit]}"
tags="${args[--tags]}"
skip_tags="${args[--skip-tags]}"
rolling="${args[--rolling]}"
playbook="${args[--playbook]}"
verbose="${args[--verbose]}"

playbook_args=("$playbook")
if [[ -n "$limit" ]]
then
  playbook_args+=(--limit "$limit")
fi
if [[ -n "$tags" ]]
then
  playbook_args+=(--tags "$tags")
fi
if [[ -n "$skip_tags" ]]
then
  playbook_args+=(--skip-tags "$skip_tags")
fi
if [[ -n "$rolling" ]]
then
  playbook_args+=(-e deployment_strategy=rolling)
fi
if [[ -n "$verbose" ]]
then
  playbook_args+=(-vvv)
fi
playbook_args+=("${other_args[@]}")

if ! ansible_run_playbook "${playbook_args[@]}"
then
  exit 1
fi
ansible_handover
if is_container_running connect
then
  playground container wait-for-connect-rest-api-ready --max-wait 300
fi
