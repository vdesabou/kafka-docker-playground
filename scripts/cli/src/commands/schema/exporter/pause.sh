# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
name="${args[--name]}"
verbose="${args[--verbose]}"

get_sr_url_and_security
sr_exporter_check_available || exit 1
sr_request PUT "/exporters/${name}/pause" || sr_exit_on_error "exporter ${name}"
log "⏸️ exporter ${name} paused"
