link="${args[--link]}"

if [[ "$(uname -s)" != "Darwin" ]]
then
    logerror "❌ Alfred is only available on macOS"
    exit 1
fi

source_dir="$root_folder/scripts/alfred-workflow"
if [ ! -f "$source_dir/info.plist" ] || [ ! -f "$source_dir/kdp.py" ]
then
    logerror "❌ $source_dir does not contain the workflow (info.plist, kdp.py)"
    exit 1
fi

if [ ! -d "/Applications/Alfred 5.app" ]
then
    logwarn "🎩 Alfred 5 is not in /Applications: get it from https://www.alfredapp.com (workflows need the Powerpack)"
fi

bundle_id=$(plutil -extract bundleid raw "$source_dir/info.plist")
version=$(plutil -extract version raw "$source_dir/info.plist")

if [[ -n "$link" ]]
then
    # Alfred preferences: the sync folder when one is set (Alfred Preferences > Advanced), else the default one
    prefs_dir="$HOME/Library/Application Support/Alfred/Alfred.alfredpreferences"
    sync_folder=$(defaults read com.runningwithcrayons.Alfred-Preferences syncfolder 2>/dev/null)
    if [ -n "$sync_folder" ]
    then
        prefs_dir="${sync_folder/#\~/$HOME}/Alfred.alfredpreferences"
    fi
    workflows_dir="$prefs_dir/workflows"
    if [ ! -d "$workflows_dir" ]
    then
        logerror "❌ Alfred workflows folder $workflows_dir not found: open Alfred Preferences once, or install without --link"
        exit 1
    fi
    target="$workflows_dir/kafka-docker-playground-kdp"
    if [ -e "$target" ] && [ ! -L "$target" ]
    then
        logerror "❌ $target exists and is not a symlink: delete that workflow in Alfred Preferences first"
        exit 1
    fi
    # an imported copy with the same bundle id would clash with the link
    for plist in "$workflows_dir"/*/info.plist
    do
        [ -f "$plist" ] || continue
        dir=$(dirname "$plist")
        [ "$dir" = "$target" ] && continue
        if [ "$(plutil -extract bundleid raw "$plist" 2>/dev/null)" = "$bundle_id" ]
        then
            logwarn "⚠️ $dir is another copy of this workflow ($bundle_id): delete it in Alfred Preferences > Workflows"
        fi
    done
    ln -sfn "$source_dir" "$target"
    log "🔗 $target -> $source_dir"
    log "👏 kdp workflow $version linked: changes to $source_dir are live (open Alfred Preferences > Workflows once if kdp does not show up)"
    exit 0
fi

# kept after the command returns: Alfred reads the file once its import dialog is confirmed
out_dir="${TMPDIR:-/tmp}"
out_dir="${out_dir%/}/kdp-alfred-workflow"
rm -rf "$out_dir"
mkdir -p "$out_dir/build"
# -L: copy the icon, which is a symlink to docs/assets
cp -RL "$source_dir/." "$out_dir/build/"
rm -rf "$out_dir/build/__pycache__"
# the imported copy lives in the Alfred preferences: point it to this clone
plutil -replace userconfigurationconfig.0.config.default -string "$root_folder" "$out_dir/build/info.plist"

bundle="$out_dir/kdp.alfred5workflow"
if ! (cd "$out_dir/build" && zip -q -r "$bundle" . -x '.*' -x '__pycache__/*')
then
    logerror "❌ failed to build $bundle"
    exit 1
fi

log "🎩 Opening $bundle in Alfred: confirm the import (kafka-docker-playground folder: $root_folder)"
if ! open "$bundle"
then
    logerror "❌ could not open $bundle: double-click it in the Finder"
    exit 1
fi
log "👏 type 'kdp' in Alfred once imported. Run this command again after a git pull to update the workflow ($version)"
