cfk_version="${args[--cfk-version]}"
operator_tag="${args[--operator-tag]}"
bundle="${args[--bundle]}"
only_show_url="${args[--only-show-url]}"
checkout_only="${args[--checkout-only]}"
grep_text="${args[--grep]}"
compare_with="${args[--compare-with]}"

repo="confluentinc/confluent-operator"
repo_root_folder="/tmp/cfk-operator-sourcecode"

# CFK version (3.3.0) or operator tag (0.1718.10) -> operator tag: the helm chart version, also the image tag of the
# operator and the git tag (v0.1718.10) of its source. From the tables of cfk-analysis/environment.py, then of
# environment/cfk/start.sh
function cfk_operator_tag () {
    local version="${1#v}"
    if [[ "$version" == 0.* ]]
    then
        echo "$version"
        return
    fi
    local tag
    tag=$(grep -oE "'0\.[0-9]+\.[0-9]+': '${version//./\\.}'" "$root_folder/cfk-analysis/environment.py" | head -1 | cut -d "'" -f 2)
    if [ -z "$tag" ]
    then
        tag=$(grep -E "^ *${version//./\\.}\) echo \"" "$root_folder/environment/cfk/start.sh" | head -1 | grep -oE '"[0-9.]+"' | tr -d '"')
    fi
    echo "$tag"
}

# operator tag -> CFK version, for the display
function cfk_release_of_tag () {
    grep -oE "'${1//./\\.}': '[0-9.]+'" "$root_folder/cfk-analysis/environment.py" | head -1 | cut -d "'" -f 4
}

# operator tag of a CFK support bundle (folder, .tar(.gz), .tgz or .zip): "Operator Version" or the chart version of
# its cluster-details.txt, else the image of the operator Deployment
function cfk_bundle_operator_tag () {
    local path="$1"
    local text=""
    if [ -d "$path" ]
    then
        local file
        file=$(find "$path" -name cluster-details.txt 2>/dev/null | head -1)
        [ -n "$file" ] && text=$(cat "$file")
        if [ -z "$text" ]
        then
            file=$(find "$path" -path "*operator*" -name "deployment.yaml" 2>/dev/null | head -1)
            [ -n "$file" ] && text=$(cat "$file")
        fi
    elif [[ "$path" == *.zip ]]
    then
        text=$(unzip -p "$path" '*cluster-details.txt' 2>/dev/null)
        [ -z "$text" ] && text=$(unzip -p "$path" '*operator/deployment.yaml' 2>/dev/null)
    else
        local member
        member=$(tar -tf "$path" 2>/dev/null | grep -E '(^|/)cluster-details\.txt$' | head -1)
        [ -n "$member" ] && text=$(tar -xOf "$path" "$member" 2>/dev/null)
        if [ -z "$text" ]
        then
            member=$(tar -tf "$path" 2>/dev/null | grep -E '(^|/)operator/deployment\.yaml$' | head -1)
            [ -n "$member" ] && text=$(tar -xOf "$path" "$member" 2>/dev/null)
        fi
    fi
    local tag
    tag=$(echo "$text" | grep -oE 'Operator Version: *0\.[0-9]+\.[0-9]+' | grep -oE '0\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$tag" ] && tag=$(echo "$text" | grep -oE 'v0\.[0-9]+\.[0-9]+' | head -1 | tr -d 'v')
    [ -z "$tag" ] && tag=$(echo "$text" | grep -oE 'confluent-operator:0\.[0-9]+\.[0-9]+' | head -1 | cut -d ':' -f 2)
    echo "$tag"
}

# shallow clone of a tag in /tmp/cfk-operator-sourcecode (reused), prints the folder
function cfk_operator_checkout () {
    local tag="$1"
    local folder="$repo_root_folder/confluent-operator-v$tag"
    if [ ! -d "$folder/.git" ]
    then
        mkdir -p "$repo_root_folder"
        rm -rf "$folder"
        log "🐏 cloning $repo at tag v$tag into $folder (shallow, first time only)" >&2
        if ! git clone --quiet --depth 1 --branch "v$tag" "https://github.com/$repo.git" "$folder" > /tmp/cfk-operator-sourcecode.log 2>&1
        then
            logerror "❌ could not clone $repo at tag v$tag, see /tmp/cfk-operator-sourcecode.log" >&2
            logerror "   it is a private repository of Confluent: you need access to it (gh auth login, VPN), and the tag must exist" >&2
            tail -5 /tmp/cfk-operator-sourcecode.log >&2
            return 1
        fi
    fi
    echo "$folder"
}

# matches of a literal string in a checkout (go and yaml sources, tests and vendored code left out), at most 40
function cfk_operator_grep () {
    git -C "$1" grep -n -I -F -e "$2" -- ':!vendor' ':!**/*_test.go' ':!test/**' ':!**/testdata/**' 2>/dev/null | head -40
}

# when the whole text is not in the code (a message built from a template, fmt.Errorf("missing inter %s credentials")):
# the longest run of consecutive words of the text (10 characters at least) that is, prints it on the first line
function cfk_operator_grep_partial () {
    local folder="$1"
    local -a words
    read -r -a words <<< "$2"
    local n=${#words[@]}
    local size start part found
    for (( size = n - 1; size >= 2; size-- ))
    do
        for (( start = 0; start + size <= n; start++ ))
        do
            part="${words[*]:$start:$size}"
            if [ ${#part} -lt 10 ]
            then
                continue
            fi
            found=$(cfk_operator_grep "$folder" "$part")
            if [ -n "$found" ]
            then
                echo "$part"
                echo "$found"
                return 0
            fi
        done
    done
    return 1
}

# prints the matches with their GitHub link: $1 tag, then the matches on stdin
function cfk_operator_print_matches () {
    while IFS= read -r line
    do
        echo "  $line  ->  https://github.com/$repo/blob/v$1/$(echo "$line" | cut -d ':' -f 1)#L$(echo "$line" | cut -d ':' -f 2)"
    done
}

nb_sources=0
[ -n "$cfk_version" ] && nb_sources=$((nb_sources + 1))
[ -n "$operator_tag" ] && nb_sources=$((nb_sources + 1))
[ -n "$bundle" ] && nb_sources=$((nb_sources + 1))
if [ $nb_sources -ne 1 ]
then
    logerror "❌ give one of --cfk-version, --operator-tag or --bundle"
    exit 1
fi

if [ -n "$bundle" ]
then
    if [ ! -e "$bundle" ]
    then
        logerror "❌ bundle not found: $bundle"
        exit 1
    fi
    tag=$(cfk_bundle_operator_tag "$bundle")
    if [ -z "$tag" ]
    then
        logerror "❌ no operator version in $bundle (cluster-details.txt, operator/deployment.yaml): use --cfk-version or --operator-tag"
        exit 1
    fi
    log "📦 operator version of the bundle: $tag"
else
    tag=$(cfk_operator_tag "${cfk_version:-$operator_tag}")
    if [ -z "$tag" ]
    then
        logerror "❌ unknown CFK version ${cfk_version}: give the operator tag (helm chart version, 0.1718.10) with --operator-tag"
        exit 1
    fi
fi
release=$(cfk_release_of_tag "$tag")
url="https://github.com/$repo/tree/v$tag"
log "🏷️  CFK ${release:-?} = operator tag $tag = git tag v$tag"

compare_tag=""
if [ -n "$compare_with" ]
then
    compare_tag=$(cfk_operator_tag "$compare_with")
    if [ -z "$compare_tag" ]
    then
        logerror "❌ unknown CFK version for --compare-with: $compare_with (or give an operator tag, 0.1718.10)"
        exit 1
    fi
    compare_release=$(cfk_release_of_tag "$compare_tag")
fi

if [[ -n "$only_show_url" ]]
then
    echo "$url"
    if [ -n "$compare_tag" ]
    then
        echo "https://github.com/$repo/compare/v$tag...v$compare_tag"
    fi
    exit 0
fi

if ! command -v git > /dev/null 2>&1
then
    logerror "❌ git is not installed"
    exit 1
fi

folder=$(cfk_operator_checkout "$tag") || exit 1

if [ -n "$grep_text" ]
then
    matches=$(cfk_operator_grep "$folder" "$grep_text")
    if [ -n "$matches" ]
    then
        log "🔎 \"$grep_text\" in CFK ${release:-$tag} ($(echo "$matches" | wc -l | tr -d ' ') match(es), tests and vendor left out):"
        echo "$matches" | cfk_operator_print_matches "$tag"
    elif partial=$(cfk_operator_grep_partial "$folder" "$grep_text")
    then
        # the message is built from a template: compare the part found
        grep_text=$(echo "$partial" | head -1)
        matches=$(echo "$partial" | tail -n +2)
        log "🔎 the whole text is not in CFK ${release:-$tag} (a message built from a template, fmt.Errorf(\"… %s …\")): \"$grep_text\" is ($(echo "$matches" | wc -l | tr -d ' ') match(es)):"
        echo "$matches" | cfk_operator_print_matches "$tag"
    else
        logwarn "🔎 \"$grep_text\" not found in CFK ${release:-$tag}, nor 2 consecutive words of it: check the spelling, or search another part"
    fi
    if [ -n "$compare_tag" ]
    then
        compare_folder=$(cfk_operator_checkout "$compare_tag") || exit 1
        compare_matches=$(cfk_operator_grep "$compare_folder" "$grep_text")
        if [ -n "$matches" ] && [ -z "$compare_matches" ]
        then
            log "🆚 not in CFK ${compare_release:-$compare_tag}: the message (or the code that logs it) changed or was removed"
        elif [ -z "$matches" ] && [ -n "$compare_matches" ]
        then
            log "🆚 in CFK ${compare_release:-$compare_tag} only ($(echo "$compare_matches" | wc -l | tr -d ' ') match(es))"
        elif [ -n "$compare_matches" ]
        then
            log "🆚 also in CFK ${compare_release:-$compare_tag}: files that changed between the two versions:"
            echo "$matches" | cut -d ':' -f 1 | sort -u | while IFS= read -r file
            do
                if ! cmp -s "$folder/$file" "$compare_folder/$file"
                then
                    echo "  $file  (changed: https://github.com/$repo/compare/v$tag...v$compare_tag)"
                else
                    echo "  $file  (same)"
                fi
            done
        fi
    fi
elif [ -n "$compare_tag" ]
then
    compare_folder=$(cfk_operator_checkout "$compare_tag") || exit 1
    log "🆚 changes between CFK ${release:-$tag} and ${compare_release:-$compare_tag}: https://github.com/$repo/compare/v$tag...v$compare_tag"
    log "   checkout of ${compare_release:-$compare_tag}: $compare_folder"
fi

if [[ -z "$checkout_only" && -z "$grep_text" && -z "$compare_tag" ]]
then
    log "🔗 $url"
fi
# last line: the folder of the checkout, for scripts and agents
echo "$folder"
