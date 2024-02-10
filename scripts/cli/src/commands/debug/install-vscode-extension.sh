tmp_dir=$(mktemp -d -t playground)
trap 'rm -rf $tmp_dir' EXIT

extension_dir=$tmp_dir/extension

mkdir $extension_dir
cd $extension_dir

log "🪄 Installing Shell Script Command Completion extension"

curl -s -L https://tetradresearch.gallery.vsassets.io/_apis/public/gallery/publisher/tetradresearch/extension//vscode-h2o/latest/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage -o extension.zip
unzip extension.zip > /dev/null 2>&1

if [ ! -f extension/out/cacheFetcher.js ]
then
  logerror "❌ cacheFetcher.js is not present !"
  exit 1
fi

if grep 'https://raw.githubusercontent.com/yamaton/h2o-curated-data/main/${kind}/json/${name}.json' extension/out/cacheFetcher.js
then
    sed -i -E -e "s|https://raw.githubusercontent.com/yamaton/h2o-curated-data/main/\${kind}/json/\${name}.json|https://raw.githubusercontent.com/vdesabou/kafka-docker-playground/master/scripts/cli/playground.json|g" extension/out/cacheFetcher.js > /dev/null 2>&1
    zip -r extension.zip extension > /dev/null 2>&1
    mv extension.zip extension.vsix

    set +e
    code --uninstall-extension extension.vsix > /dev/null 2>&1

    code --install-extension extension.vsix > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        log "👏 extension is now installed"
    else
        logerror "❌ Failed to install Shell Script Command Completion extension"
    fi
else
  logerror "❌ cannot retrieve experimental url"
  exit 1
fi

