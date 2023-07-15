only_show_url="${args[--only-show-url]}"
if [ ! -f /tmp/playground-run ]
then
    logerror "File containing re-run command /tmp/playground-run does not exist!"
    logerror "Make sure to use <playground run> command !"
    exit 1
fi

test_file=$(cat /tmp/playground-run | awk '{ print $4}')

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from /tmp/playground-run does not exist!"
    logerror "Make sure to use <playground run> command !"
    exit 1
fi

readme_file="$(dirname $test_file)/README.md"
if [ ! -f $readme_file ]
then 
    logerror "README file $readme_file does not exist"
    exit 1
fi

string=$(grep "Quickly test " $readme_file)
url=$(echo "$string" | grep -oE 'https?://[^ ]+')
url=${url//)/}

if [[ $url =~ "http" ]]
then
    short_url=$(echo $url | cut -d '#' -f 1)
    if [[ -n "$only_show_url" ]]
    then
        log "🌐 documentation is available at:"
        echo "$short_url"
    else
        log "🌐 opening documentation $short_url"
        open "$short_url"
    fi
else
    logerror "Could not find documentation link in README file $readme_file"
    exit 1
fi