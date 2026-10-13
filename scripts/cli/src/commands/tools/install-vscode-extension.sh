tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

upstream_id="tetradresearch.vscode-h2o"
# installed under its own name, so that VS Code never auto-updates it with the unpatched marketplace version
patched_name="vscode-h2o-playground"
upstream_url='https://raw.githubusercontent.com/yamaton/h2o-curated-data/main/${kind}/json/${name}.json'
playground_url="https://raw.githubusercontent.com/vdesabou/kafka-docker-playground/master/scripts/cli/playground.json"

# the extension ships a native h2o binary: download the build of this platform
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) target_platform="darwin-arm64" ;;
    Darwin-x86_64) target_platform="darwin-x64" ;;
    Linux-x86_64) if [ -f /etc/alpine-release ]; then target_platform="alpine-x64"; else target_platform="linux-x64"; fi ;;
    Linux-aarch64|Linux-arm64) target_platform="linux-arm64" ;;
    *)
        logerror "❌ platform $(uname -s) $(uname -m) is not supported"
        exit 1
    ;;
esac

extension_dir=$tmp_dir/extension

mkdir "$extension_dir"
cd "$extension_dir" || exit 1

log "🪄 Installing Shell Script Command Completion extension ($target_platform)"

version=$(curl -fsS -X POST https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery \
    -H 'Accept: application/json;api-version=7.2-preview.1' -H 'Content-Type: application/json' \
    -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"$upstream_id\"}],\"pageSize\":1}],\"flags\":17}" \
    | jq -r --arg p "$target_platform" '[.results[0].extensions[0].versions[] | select(.targetPlatform == $p or .targetPlatform == null)][0].version // empty')
if [ -z "$version" ]
then
    logerror "❌ could not find a version of $upstream_id for $target_platform on the marketplace"
    exit 1
fi

if ! curl -fsSL --compressed "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/tetradresearch/vsextensions/vscode-h2o/$version/vspackage?targetPlatform=$target_platform" -o extension.zip
then
    logerror "❌ failed to download $upstream_id $version for $target_platform"
    exit 1
fi
unzip -q extension.zip > /dev/null 2>&1

if [ ! -f extension/out/cacheFetcher.js ] || [ ! -f extension/package.json ] || [ ! -f extension.vsixmanifest ]
then
    logerror "❌ cacheFetcher.js, package.json or extension.vsixmanifest is not present in $upstream_id $version !"
    exit 1
fi

if ! grep -qF "$upstream_url" extension/out/cacheFetcher.js
then
    logerror "❌ cannot retrieve experimental url in $upstream_id $version"
    exit 1
fi

# "Load Command Spec (experimental)" downloads the playground command spec instead of h2o-curated-data
# (no sed -E and no sed -i: they do not behave the same with GNU and BSD sed)
sed -e 's|https://raw.githubusercontent.com/yamaton/h2o-curated-data/main/\${kind}/json/\${name}\.json|'"$playground_url"'|g' extension/out/cacheFetcher.js > cacheFetcher.js.tmp
mv cacheFetcher.js.tmp extension/out/cacheFetcher.js
sed -e 's|"name": "vscode-h2o"|"name": "'"$patched_name"'"|' -e 's|"displayName": "Shell Script Command Completion"|"displayName": "Shell Script Command Completion (kafka-docker-playground)"|' extension/package.json > package.json.tmp
mv package.json.tmp extension/package.json
sed -e 's|Id="vscode-h2o"|Id="'"$patched_name"'"|' extension.vsixmanifest > vsixmanifest.tmp
mv vsixmanifest.tmp extension.vsixmanifest

if ! grep -qF "$playground_url" extension/out/cacheFetcher.js || ! grep -qF "\"name\": \"$patched_name\"" extension/package.json || ! grep -qF "Id=\"$patched_name\"" extension.vsixmanifest
then
    logerror "❌ failed to patch $upstream_id $version"
    exit 1
fi

if ! zip -q -r extension.zip extension extension.vsixmanifest
then
    logerror "❌ failed to package the extension"
    exit 1
fi
mv extension.zip extension.vsix

# the upstream extension registers the same commands: keep only one of them
if code --list-extensions 2>/dev/null | grep -qix "$upstream_id"
then
    log "🧹 uninstalling $upstream_id, replaced by tetradresearch.$patched_name"
    code --uninstall-extension "$upstream_id" > /dev/null 2>&1
fi

if code --install-extension extension.vsix --force > /dev/null 2>&1
then
    log "👏 extension is now installed (tetradresearch.$patched_name $version)"
else
    logerror "❌ Failed to install Shell Script Command Completion extension"
    exit 1
fi
