connector_plugin="${args[--connector-plugin]}"
connector_tags="${args[--connector-tag]}"
only_show_url="${args[--only-show-url]}"
compile="${args[--compile]}"
compile_jdk_version="${args[--compile-jdk-version]}"
verbose="${args[--compile-verbose]}"
forced_url="${args[--forced-url]}"
open="${args[--open]}"
checkout_only="${args[--checkout-only]}"
log_flag="${args[--log]}"
files_flag="${args[--files]}"
path_glob="${args[--path]}"
grep_regex="${args[--grep]}"
json="${args[--json]}"

# with --json, everything printed goes to stderr and the JSON document to fd 3 (stdout)
exec 3>&1
if [[ -n "$json" ]]
then
    exec 1>&2
fi

function get_version_from_cc_docker_connect_cache_versions_env () {
    arg_version="$1"

    tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
    if [ -z "$PG_VERBOSE_MODE" ]
    then
        trap 'rm -rf $tmp_dir' EXIT
    else
        log "🐛📂 not deleting tmp dir $tmp_dir"
    fi
    # confluent only
    if [ "$arg_version" != "latest" ]
    then
        if [ -z $GH_TOKEN ] && [ -z $GITHUB_TOKEN ]
        then
            logerror "❌ --connector-tag set with $arg_version using fully managed connector plugin but neither GITHUB_TOKEN or GH_TOKEN environment variable are set"
            exit 1
        fi
        token="$GITHUB_TOKEN"
        if [ ! -z $GH_TOKEN ]
        then
            token="$GH_TOKEN"
        fi
        curl -H "Authorization: Token $token" -s "https://raw.githubusercontent.com/confluentinc/cc-docker-connect/refs/tags/v$arg_version/cc-connect/cache-versions.env" -o $tmp_dir/cache-versions.env

        if [ ! -f $tmp_dir/cache-versions.env ]
        then
            logerror "❌ could not download cache-versions.env from https://raw.githubusercontent.com/confluentinc/cc-docker-connect/refs/tags/v$arg_version/cc-connect/cache-versions.env"
            exit 1
        fi
    else
        cd $tmp_dir > /dev/null
        get_3rdparty_file "cache-versions.env" > /dev/null
        cd - > /dev/null
    fi

    if [ -f $tmp_dir/cache-versions.env ]
    then
        version=$(grep "$connector_name_cache_versions" $tmp_dir/cache-versions.env | cut -d "=" -f 2)
        if [ $ret -eq 0 ]
        then
            if [ "$arg_version" != "latest" ]
            then
                log "✨ --connector-tag is set with $arg_version, using version on cc-docker-connect (cache-versions.env file https://raw.githubusercontent.com/confluentinc/cc-docker-connect/refs/tags/v$cc_connect_image_version/cc-connect/cache-versions.env) which is $version"
            else
                log "✨ --connector-tag was not set, using latest version on cc-docker-connect (cache-versions.env file https://github.com/confluentinc/cc-docker-connect/blob/master/cc-connect/cache-versions.env) which is $version"
            fi
            connector_tag="$version"
        else
            logerror "❌ could not find $connector_name_cache_versions in $tmp_dir/cache-versions.env"
            exit 1
        fi
    else
        logerror "❌ file cache-versions.env could not be downloaded from s3 bucket, make sure your aws creds are set"
        exit 1
    fi
}

function get_latest_version_from_confluent_hub () {
    last_version=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --latest 2>/dev/null)
    if [[ -n "$last_version" ]]
    then
        log "✨ --connector-tag was not set, using latest version on hub $last_version"
        connector_tag="$last_version"
    else
        logwarn "could not find latest version using <playground connector-plugin versions --connector-plugin \"$connector_plugin\" --latest>"
        logerror "❌ --connector-tag flag is set 2 times, but one of them is set to latest. Comparison between version can only works when providing versions"
        exit 1
    fi
}

function check_if_ready_to_continue()
{
  if [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
      # running with github actions, continue
      return
  fi
  read -p "👍 are you ready to build (y)?" choice
  case "$choice" in
  y|Y ) ;;
  * ) logwarn "invalid response <$choice>! Please enter y."; check_if_ready_to_continue;;
  esac
}

function check_if_compile()
{
  if [ ! -z "$GITHUB_RUN_NUMBER" ] || [ ! -t 0 ]
  then
      recompile="0"
      # running with github actions, continue
      return
  fi
  read -p "👷 do you want to compile anyway (y/n)?" choice
  case "$choice" in
  y|Y ) recompile="1";;
  n|N ) recompile="0";;
  * ) logwarn "invalid response <$choice>! Please enter y or n."; check_if_compile;;
  esac
}

function check_if_delete_folder()
{
    # no question without a terminal (read would get an empty answer forever): keep the folder
    if [ ! -z "$GITHUB_RUN_NUMBER" ] || [ ! -t 0 ] || [[ -n "$checkout_only" ]]
    then
        return
    fi

    logwarn "📂 directory ${repo_folder} already exists."
    echo ""
    read -p "🧹 do you want to delete it ? (y/n)?" choice
    case "$choice" in
    y|Y ) rm -rf "${repo_folder}";;
    n|N ) ;;
    * ) logwarn "invalid response <$choice>! Please enter y or n."; check_if_delete_folder;;
    esac
}

# GET on the GitHub API: gh when it is logged in (private repositories, higher rate limit), else curl with GH_TOKEN / GITHUB_TOKEN if set
function sourcecode_github_api () {
    local api_path="$1"
    if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1
    then
        gh api -X GET "$api_path" 2>/dev/null
    else
        local token="${GH_TOKEN:-$GITHUB_TOKEN}"
        if [[ -n "$token" ]]
        then
            curl -s -f -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "https://api.github.com/$api_path"
        else
            curl -s -f -H "Accept: application/vnd.github+json" "https://api.github.com/$api_path"
        fi
    fi
}

# --log / --files: commits and changed files between two tags, from the GitHub compare API
function sourcecode_compare () {
    local repo_url="$1" ref_old="$2" ref_new="$3"
    local repo page compare_dir
    repo=$(echo "$repo_url" | sed -E 's#^https?://github.com/##; s#\.git$##; s#/$##')
    compare_dir=$(mktemp -d -t pg-XXXXXXXXXX)
    # 100 commits / files per page, 10 pages at most
    for page in 1 2 3 4 5 6 7 8 9 10
    do
        if ! sourcecode_github_api "repos/$repo/compare/$ref_old...$ref_new?per_page=100&page=$page" > "$compare_dir/page-$page.json" || ! jq -e '.commits' "$compare_dir/page-$page.json" > /dev/null 2>&1
        then
            if [ $page -eq 1 ]
            then
                logerror "❌ could not compare $ref_old...$ref_new in github.com/$repo (tags missing, private repository without GH_TOKEN, or GitHub API rate limit)"
                rm -rf "$compare_dir"
                exit 1
            fi
            rm -f "$compare_dir/page-$page.json"
            break
        fi
        if [ "$(jq '.commits | length' "$compare_dir/page-$page.json")" -lt 100 ] && [ "$(jq '.files // [] | length' "$compare_dir/page-$page.json")" -lt 100 ]
        then
            break
        fi
    done
    jq -s --arg repo "$repo" --arg old "$ref_old" --arg new "$ref_new" --arg grep "$grep_regex" '
        {
            repository: $repo, from: $old, to: $new,
            total_commits: .[0].total_commits,
            commits: ([.[].commits[]] | unique_by(.sha) | sort_by(.commit.committer.date) | reverse
                | map({sha: .sha[0:9], date: .commit.committer.date[0:10], author: .commit.author.name, message: (.commit.message | split("\n")[0]), merge: ((.parents | length) > 1)})),
            files: ([.[].files // [] | .[]] | unique_by(.filename) | map({file: .filename, status, additions, deletions, patch}))
        }
        | .nb_merges = ([.commits[] | select(.merge)] | length)
        | .commits |= map(select(.merge | not))
        | if $grep != "" then .commits |= map(select(.message | test($grep; "i"))) else . end' "$compare_dir"/page-*.json > "$compare_dir/compare.json"

    if [[ -n "$path_glob" ]]
    then
        jq -r '.files[].file' "$compare_dir/compare.json" | while IFS= read -r f
        do
            [[ "$f" == $path_glob ]] && echo "$f"
        done | jq -R . | jq -s . > "$compare_dir/kept.json"
        jq --slurpfile kept "$compare_dir/kept.json" '.files |= map(select(.file as $f | $kept[0] | index($f)))' "$compare_dir/compare.json" > "$compare_dir/compare.tmp" && mv "$compare_dir/compare.tmp" "$compare_dir/compare.json"
    fi

    if [[ -n "$json" ]]
    then
        jq --arg url "$sourcecode_url" --arg log "$log_flag" --arg files "$files_flag" --arg path "$path_glob" '
            {repository, from, to, url: $url, total_commits}
            + (if $log != "" then {commits, nb_merges} else {} end)
            + (if $files != "" then {files: (if $path != "" then .files else (.files | map(del(.patch))) end)} else {} end)' "$compare_dir/compare.json" >&3
        rm -rf "$compare_dir"
        return
    fi

    local c="$compare_dir/compare.json"
    if [[ -n "$log_flag" ]]
    then
        log "📜 $(jq '.commits | length' $c) commit(s) from $ref_old to $ref_new in github.com/$repo${grep_regex:+ matching \"$grep_regex\"}, newest first ($(jq .nb_merges $c) merge commit(s) left out)"
        jq -r '.commits[] | "   \(.date) \(.sha) \(.message) (\(.author))"' $c
        if [ "$(jq '.total_commits' $c)" -gt 1000 ]
        then
            logwarn "⚠️ $(jq '.total_commits' $c) commits in total: only the first 1000 are read"
        fi
    fi
    if [[ -n "$files_flag" ]]
    then
        log "🗂️ $(jq '.files | length' $c) file(s) changed from $ref_old to $ref_new${path_glob:+ matching $path_glob}"
        jq -r '.files[] | "   \(.status | .[0:1] | ascii_upcase) \(.file) +\(.additions) -\(.deletions)"' $c
        if [[ -n "$path_glob" ]]
        then
            jq -r '.files[] | "\n📄 \(.file)\n\(.patch // "   (no patch: binary or too large, see the compare url)")"' $c
        fi
    fi
    rm -rf "$compare_dir"
}

# --grep with one version: matches in the checkout, file:line
function sourcecode_grep () {
    local folder="$1" regex="$2"
    local matches
    matches=$(cd "$folder" && grep -rnIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=target -- "$regex" . 2>/dev/null | sed 's#^\./##' | head -500)
    if [[ -n "$json" ]]
    then
        printf '%s\n' "$matches" | grep -v '^$' | jq -R 'capture("^(?<file>[^:]+):(?<line>[0-9]+):(?<text>.*)$") | .line |= tonumber' | jq -s --arg folder "$folder" --arg p "$connector_plugin" --arg tag "$connector_tag" --arg url "$sourcecode_url" --arg regex "$regex" \
            '{connector_plugin: $p, version: $tag, url: $url, checkout_folder: $folder, grep: $regex, matches: .}' >&3
        return
    fi
    local nb
    nb=$(printf '%s\n' "$matches" | grep -c . || true)
    if [ "$nb" == "0" ]
    then
        logwarn "🤷 no match for \"$regex\" in $folder"
        return
    fi
    log "🔎 $nb match(es) for \"$regex\" in $folder$( [ "$nb" -ge 500 ] && echo " (first 500)")"
    printf '%s\n' "$matches" >&3
}

function compile () {
    arg_version="$1"

    if [[ "$sourcecode_url" != *"github.com"* ]]
    then
        logerror "❌ --compile, --open or --checkout-only flag does not work when sourcecode is not hosted on github"
        exit 1
    fi

    if [[ $(type -f git 2>&1) =~ "not found" ]]
    then
        logerror "❌ --compile, --open or --checkout-only flag is set but git command is not installed"
        exit 1
    fi

    # --- 1. Parse the URL ---
    # Regex to capture:
    # 1: The base repo URL (e.g., https://github.com/user/repo)
    # 4: The tag/branch name (e.g., v1.3.30)
    regex="^(https:(//)[^/]+/[^/]+/[^/]+)/(tree|blob)/([^/]+)"

    if [[ "$sourcecode_url" =~ $regex ]]; then
        # URL has a /tree/ or /blob/ part
        repo_url="${BASH_REMATCH[1]}.git"
        tag_name="${BASH_REMATCH[4]}"
        repo_name=$(basename "${BASH_REMATCH[1]}")
        
        log "🏷️  tag/branch: $tag_name"
        log "🔗 base repo url: $repo_url"
        log "🧑‍💻 repo directory: $repo_name"
        
        # --depth 1: Downloads only that commit, not the full history (much faster)
        # --branch $tag_name: Checks out the specific tag or branch
        clone_command="git clone --recursive --depth 1 --branch $tag_name $repo_url"
    else
        # URL is a standard repo URL (no /tree/ or /blob/) 
        # Append .git if it's not already there
        temp_url="${sourcecode_url%/}"
        if [[ "$temp_url" != *.git ]]; then
            repo_url="${temp_url}.git"
        else
            repo_url="$temp_url"
        fi
        
        repo_name=$(basename "$repo_url" .git)
        log "🔗 repo url: $repo_url"
        log "🧑‍💻 repo directory: $repo_name"
        
        # Clone default branch, but still use --depth 1 for speed
        clone_command="git clone --recursive --depth 1 $repo_url"
    fi
    repo_root_folder="/tmp/connector-plugin-sourcecode"
    mkdir -p "${repo_root_folder}"
    repo_folder="${repo_root_folder}/${repo_name}-${arg_version}"
    # --- 2. Checkout (Clone) Project ---
    if [ -d "${repo_folder}" ] && { [ ! -f "${repo_folder}/.git/HEAD" ] || [ -n "$(git -C "${repo_folder}" ls-files --deleted 2>/dev/null | head -1)" ]; }
    then
        # the periodic cleanup of /tmp (macOS: files untouched for 3 days) deletes the files and keeps the folders
        logwarn "📂 the checkout in ${repo_folder} is incomplete (files deleted by the cleanup of /tmp?), cloning it again"
        rm -rf "${repo_folder}"
    fi
    if [ -d "${repo_folder}" ]
    then
        check_if_delete_folder
    fi

    if [ ! -d "${repo_folder}" ]
    then
        log "🐏🐏 cloning github repository with git command <$clone_command>"
        cd ${repo_root_folder} > /dev/null 2>&1
        set +e
        $clone_command > /tmp/result.log 2>&1
        if [ $? != 0 ]
        then
            logerror "❌ git clone command <$clone_command> failed"
            cat /tmp/result.log
            exit 1
        fi
        set -e
        mv "${repo_root_folder}/${repo_name}" "${repo_folder}"
        mkdir -p ${repo_folder}/.vscode
        cp ${root_folder}/scripts/cli/launch.json ${repo_folder}/.vscode/
        cd - > /dev/null 2>&1
    fi
    if [[ "${repo_name}" == *-private ]]
    then
        if [[ "${repo_name}" == "kafka-connect-cosmosdb-v2-private" ]]
        then
            # specific case
            repo_folder="${repo_folder}/azure-sdk-for-java"
        elif [[ "${repo_name}" == "kafka-connect-couchbasedb-private" ]]
        then
            # specific case
            repo_folder="${repo_folder}/kafka-connect-couchbase"
        elif [[ "${repo_name}" == "debezium-v2-private" ]]
        then
            # specific case
            repo_folder="${repo_folder}/debezium"
        elif [[ "${repo_name}" == "kafka-connect-redis-private" ]]
        then
            # specific case
            repo_folder="${repo_folder}/redis-kafka-connect"
        elif [[ "${repo_name}" == "kafka-connect-s3-private" ]]
        then
            # specific case
            repo_folder="${repo_folder}/kafka-connect-storage-cloud"
        else
            repo_folder="${repo_folder}/${repo_name%-private}"
        fi
    fi
    if [[ -n "$checkout_only" ]]
    then
        log "📂 sourcecode checked out in folder:"
        echo "${repo_folder}"
        return
    fi

    if [[ -n "$compile" ]]
    then
        if [ ! -f "${repo_folder}/pom.xml" ]
        then
            logerror "❌ there is no pom.xml file in ${repo_folder}. Only maven projects can be compiled for now."
            exit 1
        fi

        # --- Determine compile_jdk_version from pom.xml if not explicitly provided ---
        # This looks first for maven-compiler-plugin <release> or <source>/<target> in the plugin
        # and then for properties maven.compiler.release / maven.compiler.source / maven.compiler.target.
        # It also resolves simple property references like ${java.version} defined in the same pom.
        if [[ ! -n "$compile_jdk_version" ]]
        then
            log "🤎 --compile-jdk-version was not set, attempting to detect maven compiler version from pom.xml..."
            pom_file="${repo_folder}/pom.xml"

            # helper: resolve a single-level ${prop} reference from pom.xml
            resolve_prop() {
                val="$1"
                if [[ "$val" =~ \$\{([^}]+)\} ]]; then
                    pname="${BASH_REMATCH[1]}"
                    # look for property in pom.xml
                    pval=$(sed -n "s:.*<${pname}>\(.*\)</${pname}>.*:\1:p" "$pom_file" | head -n1)
                    if [ -n "$pval" ]; then
                        echo "$pval"
                        return
                    fi
                fi
                echo "$val"
            }

            # 1) properties
            prop_release=$(sed -n 's:.*<maven.compiler.release>\(.*\)</maven.compiler.release>.*:\1:p' "$pom_file" | head -n1)
            prop_source=$(sed -n 's:.*<maven.compiler.source>\(.*\)</maven.compiler.source>.*:\1:p' "$pom_file" | head -n1)
            prop_target=$(sed -n 's:.*<maven.compiler.target>\(.*\)</maven.compiler.target>.*:\1:p' "$pom_file" | head -n1)
            prop_debezium_source=$(sed -n 's:.*<debezium.java.source>\(.*\)</debezium.java.source>.*:\1:p' "$pom_file" | head -n1)

            # 2) plugin configuration (search the plugin block)
            plugin_block=$(sed -n '/<artifactId>maven-compiler-plugin<\/artifactId>/,/<\/plugin>/p' "$pom_file" 2>/dev/null || true)
            plugin_release=$(echo "$plugin_block" | sed -n 's:.*<release>\(.*\)</release>.*:\1:p' | head -n1)
            plugin_source=$(echo "$plugin_block" | sed -n 's:.*<source>\(.*\)</source>.*:\1:p' | head -n1)
            plugin_target=$(echo "$plugin_block" | sed -n 's:.*<target>\(.*\)</target>.*:\1:p' | head -n1)

            # order of precedence: plugin <release> > properties release > plugin <source> > properties source > plugin <target> > properties target

            # pick the first non-empty among the collected candidates
            chosen=""
            for c in "$prop_debezium_source" "$plugin_release" "$prop_release" "$plugin_source" "$prop_source" "$plugin_target" "$prop_target"; do
                if [ -n "$c" ]; then
                    chosen="$c"
                    break
                fi
            done

            if [ -n "$chosen" ]; then
                # resolve ${...}
                chosen=$(resolve_prop "$chosen")

                # normalize common formats: 1.8 -> 8, 17.0.1 -> 17
                if [[ "$chosen" =~ ^1\.([0-9]+)$ ]]; then
                    chosen="${BASH_REMATCH[1]}"
                elif [[ "$chosen" =~ ^([0-9]+) ]]; then
                    chosen="${BASH_REMATCH[1]}"
                fi

                if [ -n "$chosen" ]; then
                    compile_jdk_version="$chosen"
                    if [ "$chosen" == "8" ]
                    then
                        compile_jdk_version=11
                        log "⚠️  detected maven compiler version '$chosen' from pom.xml, but 8 is too old, forcing --compile-jdk-version to $compile_jdk_version"
                    elif [ "$chosen" == "12" ]
                    then
                        compile_jdk_version=11
                        log "⚠️  detected maven compiler version '$chosen' from pom.xml, but 12 is not supported, forcing --compile-jdk-version to $compile_jdk_version"
                    elif [ "$chosen" == "\${java.version}" ]
                    then
                        compile_jdk_version=11
                        log "⚠️  detected maven compiler version '$chosen' from pom.xml, but it is not valid, forcing --compile-jdk-version to $compile_jdk_version"
                    else
                        log "✨ detected maven compiler version '$chosen' from pom.xml, using --compile-jdk-version $compile_jdk_version"
                    fi
                fi
            fi

            if [ -z "$compile_jdk_version" ]
            then
                if [[ "${repo_name}" == *"kafka-connect-salesforce" ]]
                then
                    compile_jdk_version=17
                    log "⚠️  kafka-connect-salesforce requires Jdk 17, forcing --compile-jdk-version to $compile_jdk_version"
                else
                    compile_jdk_version=11
                    log "🤷‍♂️ could not detect maven compiler version in pom.xml, defaulting to --compile-jdk-version $compile_jdk_version"
                fi
            fi
        fi

        mvn_settings_file="/tmp/settings.xml"
        if [[ "$sourcecode_url" == *"confluentinc"* ]]
        then
            if [ $is_confluent_employee -eq 1 ]
            then
                if [ ! -d "$HOME/.cc-dotfiles" ]
                then
                    logerror "❌ you're a Confluent employee, but dev-login is not installed (directory $HOME/.cc-dotfiles does not exist), please follow:"
                    echo "🔗 Maven FAQ https://confluentinc.atlassian.net/wiki/spaces/TOOLS/pages/2930704487/Maven+FAQ#How-do-I-get-access-locally%3F"
                    exit 1
                fi

                # check_if_call_dev_login
                log "🛂 execute dev-login"
                source $HOME/.cc-dotfiles/caas.sh && dev-login -f;

                mvn_settings_file="/root/.m2/settings.xml"
            fi
        fi
    fi

    editor=$(playground config get editor)
    log "🧑‍💻 opening ${repo_folder} with editor ${editor}"
    open_file_with_editor "${repo_folder}"
    # echo ""
    # check_if_ready_to_continue

    if [[ -n "$open" ]]
    then
        return
    fi

    # Display each zip file
    found=0
    # declare -a array_zip_file_list=()
    for zip_file in $(find "${repo_folder}" -type f -name "*.zip" | sort)
    do
        if [ -f "$zip_file" ]
        then
            found=1
            log "📄 zip file $zip_file already present"
        fi
    done

    recompile=1
    if [ $found == 1 ]
    then
        log "some zip files are already present, do you want to recompile ?"
        echo "" 
        check_if_compile
    fi

    if [ $recompile == 1 ]
    then

        # --- 3. Compile with Maven ---
        file_output="${repo_folder}/playground-compilation-$repo_name.log"
        log "🏗  building with maven ${repo_folder}...it can take a while..⏳"
        log "🏗  use --compile-verbose to see full output. compilation logs are also present in ${file_output}"
        set +e

        if [[ -n "$verbose" ]]
        then
            log "🐞 --compile-verbose is set, showing full output of compilation:"
            docker run -i --rm -v "${repo_folder}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-${compile_jdk_version} mvn -s $mvn_settings_file -Dquick -Dcheckstyle.skip -DskipTests -Dlicense.skip=true -DskipITs -Dskip.unit.tests=true clean package 2>&1 | tee "$file_output"
            ret=${PIPESTATUS[0]}
        else
            docker run -i --rm -v "${repo_folder}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-${compile_jdk_version} mvn -s $mvn_settings_file -Dquick -Dcheckstyle.skip -DskipTests -Dlicense.skip=true -DskipITs -Dskip.unit.tests=true clean package > "$file_output" 2>&1
            ret=$?
        fi
        if [ $ret != 0 ]
        then
            logerror "❌ failed to build ${repo_folder}, check the logs at ${file_output}"
            exit 1
        fi
        set +e

        log "👌 build complete! zip artifacts found are:"
    else
        log "👌 zip artifacts found are:"
    fi

    find "${repo_folder}" -type f -name "*.zip" | sort
    
    echo ""
    
    # Display each zip file
    found=0
    # declare -a array_zip_file_list=()
    for zip_file in $(find "${repo_folder}" -type f -name "*.zip" | sort)
    do
        if [ -f "$zip_file" ]
        then
            found=1
            log "📄🥳 zip file $zip_file generated !"
            # array_zip_file_list+=("$zip_file")
            if [[ "$OSTYPE" == "darwin"* ]]
            then
                clipboard=$(playground config get clipboard)
                if [ "$clipboard" == "" ]
                then
                    playground config set clipboard true
                fi

                if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
                then
                    echo "$zip_file"| pbcopy
                    zip_file_name=$(basename "$zip_file")
                    log "📋 path to the zip file $zip_file_name has been copied to the clipboard (disable with 'playground config clipboard false')"
                fi
            fi
        fi
    done

    if [ $found == 0 ]
    then
        logwarn "🤷‍♂️ no zip file in '${repo_folder}', that project is probably packaging releases in different way"
    #else
        # array_declaration=$(declare -p array_zip_file_list)
        # encoded_array=$(echo "$array_declaration" | base64)
        # playground state set run.array_zip_file_list_base64 "$encoded_array"
    fi
}

########################


####################################


################################################


########################


####################################


################################################

if [[ -n "$forced_url" ]]
then
    sourcecode_url="$forced_url"
    compile "$connector_tag"

    exit 0
fi


# Convert space-separated string to array
IFS=' ' read -ra connector_tag_array <<< "$connector_tags"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    log "file $root_folder/scripts/cli/confluent-hub-plugin-list.txt not found. Generating it now, it may take a while..."
    playground generate-connector-plugin-list
fi

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    logerror "❌ file $root_folder/scripts/cli/confluent-hub-plugin-list.txt could not be generated"
    exit 1
fi

is_fully_managed=0
if [[ "$connector_plugin" == *"confluentinc"* ]] && [[ "$connector_plugin" != *"-"* ]]
then
    log "🌥️  connector plugin $connector_plugin was identified as fully managed connector"
    is_fully_managed=1
fi

set +e
is_confluent_employee=0
output=$(grep "CONFLUENT EMPLOYEE VERSION" $root_folder/scripts/cli/confluent-hub-plugin-list.txt)
ret=$?
if [ $ret -eq 0 ]
then
    is_confluent_employee=1
elif [ $is_fully_managed -eq 1 ]
then
    # the public plugin list has the source code url of self-managed plugins: only fully managed ones need the employee list
    logerror "❌ playground connector-plugin sourcecode is not working with fully managed connectors"
    logerror "❌ if you're a Confluent employee, make sure your aws creds are set and then run <playground generate-connector-plugin-list>"
    exit 1
fi

output=$(awk -F'|' -v plugin="$connector_plugin" '
{
    current=$1
    sub(/^[^[:space:]]+[[:space:]]+/, "", current)
    if (current == plugin) {
        print $0
        exit
    }
}' $root_folder/scripts/cli/confluent-hub-plugin-list.txt)
ret=$?
set -e
if [ $ret -ne 0 ]
then
    logerror "❌ could not found $connector_plugin in $root_folder/scripts/cli/confluent-hub-plugin-list.txt"
    exit 1
fi

sourcecode_url=$(echo "$output" | cut -d "|" -f 2)
if [ "$sourcecode_url" == "null" ] || [ "$sourcecode_url" == "" ]
then
    logwarn "🤷‍♂️ could not found sourcecode url for plugin $connector_plugin. It is probably proprietary"
    if [[ "$sourcecode_url" == *"confluentinc"* ]]
    then
        if [ $is_confluent_employee -eq 1 ]
        then
            logerror "❌ if you're a Confluent employee, make sure your aws creds are set and then run <playground generate-connector-plugin-list>"
            exit 1
        fi
    fi
    exit 1
fi
# remove trailing slash if any
sourcecode_url=${sourcecode_url%/}

if [ $is_confluent_employee -eq 1 ] || [ $is_fully_managed -eq 1 ]
then
    connector_name_cache_versions=$(echo "$output" | cut -d "|" -f 3)
fi



comparison_mode_versions=""
length=${#connector_tag_array[@]}
if ((length > 1))
then
    if ((length > 2))
    then
        logerror "❌ --connector-tag can only be set 2 times"
        exit 1
    fi
    
    if [[ "$sourcecode_url" != *"github.com"* ]]
    then
        logerror "❌ --connector-tag flag is set 2 times, but sourcecode is not hosted on github, comparison between version can only works with github"
        exit 1
    fi
    connector_tag1="${connector_tag_array[0]}"
    connector_tag2="${connector_tag_array[1]}"

    if [ "$connector_tag1" == "" ] || [ "$connector_tag1" == "latest" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            get_version_from_cc_docker_connect_cache_versions_env "latest"
            connector_tag1=$connector_tag
        else
            get_latest_version_from_confluent_hub
            connector_tag1=$connector_tag
        fi
    else
        if [ $is_fully_managed -eq 1 ]
        then
            get_version_from_cc_docker_connect_cache_versions_env "$connector_tag1"
            connector_tag1=$connector_tag
        fi
    fi

    if [ "$connector_tag2" == "" ] || [ "$connector_tag2" == "latest" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            get_version_from_cc_docker_connect_cache_versions_env "latest"
            connector_tag2=$connector_tag
        else
            get_latest_version_from_confluent_hub
            connector_tag2=$connector_tag
        fi
    else
        if [ $is_fully_managed -eq 1 ]
        then
            get_version_from_cc_docker_connect_cache_versions_env "$connector_tag2"
            connector_tag2=$connector_tag
        fi
    fi

    if [ "$connector_tag1" == "\\" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            logerror "❌ --connector-tag set with \" \" cannot work when using fully managed connector plugin"
            exit 1
        fi
        ret=$(choose_connector_tag "$connector_plugin")
        connector_tag1=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
    fi

    if [ "$connector_tag2" == "\\" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            logerror "❌ --connector-tag set with \" \" cannot work when using fully managed connector plugin"
            exit 1
        fi
        ret=$(choose_connector_tag "$connector_plugin")
        connector_tag2=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
    fi

    # older version first, the tags of the repository are built below (prefix and suffix depend on it)
    if version_gt $connector_tag1 $connector_tag2
    then
        connector_tag_old="$connector_tag2"
        connector_tag_new="$connector_tag1"
    else
        connector_tag_old="$connector_tag1"
        connector_tag_new="$connector_tag2"
    fi
    comparison_mode_versions="$connector_tag_old...$connector_tag_new"
else
    connector_tag="${connector_tag_array[0]}"
    if [ "$connector_tag" == "\\" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            logerror "❌ --connector-tag set with \" \" cannot work when using fully managed connector plugin"
            exit 1
        fi
        ret=$(choose_connector_tag "$connector_plugin")
        connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
    elif [ "$connector_tag" == "" ] || [ "$connector_tag" == "latest" ]
    then
        if [ $is_fully_managed -eq 0 ]
        then
            last_version=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --latest 2>/dev/null)
            if [[ -n "$last_version" ]]
            then
                log "✨ --connector-tag was not set, using latest version on hub $last_version"
                connector_tag="$last_version"
            else
                logwarn "could not find latest version using <playground connector-plugin versions --connector-plugin \"$connector_plugin\" --latest>, using latest"
                connector_tag="latest"
            fi
        else
            get_version_from_cc_docker_connect_cache_versions_env "latest"
        fi
    else
        if [ $is_fully_managed -eq 1 ]
        then
            get_version_from_cc_docker_connect_cache_versions_env "$connector_tag"
        fi
    fi
fi

maybe_tag_prefix="v"
maybe_tag_suffix=""
if [[ "$sourcecode_url" == *"confluentinc"* ]]
then
    if [[ "$sourcecode_url" == *"kafka-connect-cosmosdb" ]]
    then
        # specific case
        maybe_tag_prefix="kafka-connect-cosmos-"
    elif [[ "$sourcecode_url" == *"kafka-connect-couchbase" ]]
    then
        # specific case
        maybe_tag_prefix=""
    elif [[ "$sourcecode_url" == *"kafka-connect-spooldir" ]]
    then
        # specific case
        maybe_tag_prefix="kafka-connect-spooldir-"
    else
        # confluent use v prefix for tags example v1.5.0
        maybe_tag_prefix="v"
    fi
elif [[ "$sourcecode_url" == *"debezium/debezium"* ]]
then
    # debezium use v prefix for tags example 1.5.0
    maybe_tag_prefix="v"
    maybe_tag_suffix=".Final"
elif [[ "$sourcecode_url" == *"kafka-connect-transform-tojsonstring"* ]] || [[ "$sourcecode_url" == *"kafka-connect-zeebe"* ]] || [[ "$sourcecode_url" == *"kafka-connect-shell-source"* ]]
then
    maybe_tag_prefix=""
elif [[ "$sourcecode_url" == *"kafka-connect-mongodb"* ]]
then
    maybe_tag_prefix="r"
fi


if [ "$comparison_mode_versions" != "" ]
then
    git_ref_old="$maybe_tag_prefix$connector_tag_old$maybe_tag_suffix"
    git_ref_new="$maybe_tag_prefix$connector_tag_new$maybe_tag_suffix"
    log "✨ --connector-tag flag is set 2 times, comparison mode will be opened with versions $git_ref_old and $git_ref_new"
    additional_text=", comparing $git_ref_old and $git_ref_new"
    original_sourcecode_url="$sourcecode_url"
    sourcecode_url="$sourcecode_url/compare/$git_ref_old...$git_ref_new"
else
    additional_text=" for $connector_tag version"
    if [ "$connector_tag" != "latest" ] && [[ "$sourcecode_url" == *"github.com"* ]]
    then
        sourcecode_url="$sourcecode_url/tree/$maybe_tag_prefix$connector_tag$maybe_tag_suffix"
    fi
fi

if [[ -n "$log_flag" ]] || [[ -n "$files_flag" ]]
then
    if [ "$comparison_mode_versions" == "" ]
    then
        logerror "❌ --log and --files compare two versions: set --connector-tag 2 times"
        exit 1
    fi
    if [[ "$original_sourcecode_url" != *"github.com"* ]]
    then
        logerror "❌ --log and --files only work with source code hosted on GitHub ($original_sourcecode_url)"
        exit 1
    fi
fi
if [[ -n "$path_glob" ]] && [[ -z "$files_flag" ]]
then
    logerror "❌ --path filters the files of --files"
    exit 1
fi
if [[ -n "$grep_regex" ]] && [ "$comparison_mode_versions" != "" ] && [[ -z "$log_flag" ]]
then
    logerror "❌ with two versions, --grep filters the commits of --log: add --log (or set --connector-tag once to grep the code)"
    exit 1
fi
if [[ -n "$grep_regex" ]] && [ "$comparison_mode_versions" == "" ]
then
    # grep the code at that version: needs the checkout
    checkout_only=1
fi

if [[ -n "$json" ]]
then
    # stdout is kept for the JSON document
    log "🧑‍💻🌐 sourcecode for plugin $connector_plugin$additional_text is available at: $sourcecode_url" >&2
elif [[ -n "$only_show_url" ]] || [[ $(type -f open 2>&1) =~ "not found" ]] || [[ -n "$compile" ]] || [[ -n "$open" ]] || [[ -n "$checkout_only" ]] || [[ -n "$log_flag" ]] || [[ -n "$files_flag" ]] || [[ -n "$grep_regex" ]]
then
    log "🧑‍💻🌐 sourcecode for plugin $connector_plugin$additional_text is available at:"
    echo "$sourcecode_url"
else
    log "🧑‍💻 opening sourcecode url $sourcecode_url for plugin $connector_plugin in browser$additional_text"
    open "$sourcecode_url"
fi

if [[ -n "$log_flag" ]] || [[ -n "$files_flag" ]]
then
    sourcecode_compare "$original_sourcecode_url" "$git_ref_old" "$git_ref_new"
    exit 0
fi

if [ "$comparison_mode_versions" != "" ]
then
    if [[ -n "$compile" ]] || [[ -n "$open" ]] || [[ -n "$checkout_only" ]]
    then
        if [ "$connector_tag1" != "latest" ] && [[ "$original_sourcecode_url" == *"github.com"* ]]
        then
            sourcecode_url="$original_sourcecode_url/tree/$maybe_tag_prefix$connector_tag1$maybe_tag_suffix"
        fi
        compile "$connector_tag1"

        if [ "$connector_tag2" != "latest" ] && [[ "$original_sourcecode_url" == *"github.com"* ]]
        then
            sourcecode_url="$original_sourcecode_url/tree/$maybe_tag_prefix$connector_tag2$maybe_tag_suffix"
        fi
        skip_dev_login_check=1
        compile "$connector_tag2"
    fi
else
    # if [ "$connector_tag" != "latest" ] && [[ "$sourcecode_url" == *"github.com"* ]]
    # then
    #     sourcecode_url="$sourcecode_url/tree/$maybe_tag_prefix$connector_tag$maybe_tag_suffix"
    # fi

    if [[ -n "$compile" ]] || [[ -n "$open" ]] || [[ -n "$checkout_only" ]]
    then
        if [[ -n "$grep_regex" ]]
        then
            # the checkout logs go to stderr: stdout is for the matches
            compile "$connector_tag" >&2
        else
            compile "$connector_tag"
        fi
    fi
    if [[ -n "$grep_regex" ]]
    then
        sourcecode_grep "$repo_folder" "$grep_regex"
    elif [[ -n "$json" ]]
    then
        jq -n --arg p "$connector_plugin" --arg url "$sourcecode_url" --arg tag "$connector_tag" --arg folder "${repo_folder:-}" --argjson fm "$is_fully_managed" \
            '{connector_plugin: $p, version: $tag, url: $url, fully_managed: ($fm == 1)} + (if $folder != "" then {checkout_folder: $folder} else {} end)' >&3
    fi
fi