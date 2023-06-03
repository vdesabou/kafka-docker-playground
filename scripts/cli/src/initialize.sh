## Code here runs inside the initialize() function
## Use it for anything that you need to run before any other function, like
## setting environment variables:
## CONFIG_FILE=settings.ini
##
## Feel free to empty (but not delete) this file.

if [ -z $CONFIG_FILE ]
then
    DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
    dir1=$(echo ${DIR_CLI%/*})
    root_folder=$(echo ${dir1%/*})

    CONFIG_FILE=$root_folder/scripts/cli/config.ini
    
    # log "📝 Loading default config.ini $CONFIG_FILE as CONFIG_FILE environment variable is not set"
# else
    # log "📝 Loading config.ini $CONFIG_FILE from CONFIG_FILE environment variable"
fi