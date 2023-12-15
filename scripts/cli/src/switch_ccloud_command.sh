if [ -f /tmp/switch-playground-command ] || [ -f /tmp/switch-playground-run ]
then
    log "🌩️ you have already switched to ccloud environment"
    exit 0
fi

if [ -f /tmp/playground-command ]
then
    mv /tmp/playground-command /tmp/switch-playground-command
fi

if [ -f /tmp/playground-run ]
then
    mv /tmp/playground-run /tmp/switch-playground-run
fi

log "🌩️ switch to ccloud environment"
bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi