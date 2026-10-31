# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
name="${args[--name]}"
verbose="${args[--verbose]}"

get_sr_url_and_security
sr_exporter_check_available || exit 1
sr_request DELETE "/exporters/${name}" || sr_exit_on_error "exporter ${name} (pause it first)"
log "🗑️ exporter ${name} deleted (the exported schemas stay in the destination)"
