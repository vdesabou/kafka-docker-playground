only_show_url="${args[--only-show-url]}"
test_file=$(playground state get run.test_file)

if [ ! -f "$test_file" ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

readme_file="$(dirname "$test_file")/README.md"
if [ ! -f "$readme_file" ]
then 
    logwarn "README file $readme_file does not exist, ignoring"
    exit 0
fi

# no match is not an error (set -e): handled below
string=$(grep "Quickly test " "$readme_file" || true)
# the first link only: a README line can hold several
url=$(echo "$string" | grep -oE 'https?://[^ ]+' | head -1 || true)
url=${url//)/}

if [[ $url =~ "http" ]]
then
    short_url=$(echo "$url" | cut -d '#' -f 1)
    if [[ -z "$only_show_url" ]] && can_open_url
    then
        log "🌐 opening documentation $short_url"
        open_url "$short_url"
    else
        log "🌐 documentation is available at:"
        echo "$short_url"
    fi
elif [[ -n "$only_show_url" ]]
then
    # informational (playground status, run…): an example without documentation link must not stop them. Only connector
    # READMEs have a "Quickly test" link: warn for those only, the others (ksqldb/, other/, schema-registry/…) never had one
    if [[ "$test_file" == */connect/* ]] || [[ "$test_file" == */ccloud/fm-* ]]
    then
      logwarn "no documentation link in README file $readme_file"
    fi
else
    logerror "Could not find documentation link in README file $readme_file"
    exit 1
fi