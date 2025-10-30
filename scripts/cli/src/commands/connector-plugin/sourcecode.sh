connector_plugin="${args[--connector-plugin]}"
connector_tags="${args[--connector-tag]}"
only_show_url="${args[--only-show-url]}"
compile="${args[--compile]}"
compile_jdk_version="${args[--compile-jdk-version]}"
verbose="${args[--compile-verbose]}"

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
    log "🌥️ connector-plugin $connector_plugin was identified as fully managed connector"
    is_fully_managed=1
fi

set +e
is_confluent_employee=0
output=$(grep "CONFLUENT EMPLOYEE VERSION" $root_folder/scripts/cli/confluent-hub-plugin-list.txt)
ret=$?
if [ $ret -eq 0 ]
then
    is_confluent_employee=1
else
    logerror "❌ playground connector-plugin sourcecode is not working with fully managed connectors"
    logerror "❌ if you're a Confluent employee, make sure your aws creds are set and then run <playground generate-connector-plugin-list>"
    exit 1
fi

output=$(grep "^$connector_plugin|" $root_folder/scripts/cli/confluent-hub-plugin-list.txt)
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
    logerror "❌ could not found sourcecode url for plugin $connector_plugin. It is probably proprietary"
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

if [ $is_confluent_employee -eq 1 ] || [ $is_fully_managed -eq 1 ]
then
    connector_name_cache_versions=$(echo "$output" | cut -d "|" -f 3)
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
    output=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --last 1 | head -n 1)
    last_version=$(echo "$output" | grep -v "<unknown>" | cut -d " " -f 2 | cut -d "v" -f 2)
    if [[ -n "$last_version" ]]
    then
        log "✨ --connector-tag was not set, using latest version on hub $last_version"
        connector_tag="$last_version"
    else
        logwarn "could not find latest version using <playground connector-plugin versions --connector-plugin \"$connector_plugin\" --last 1>"
        logerror "❌ --connector-tag flag is set 2 times, but one of them is set to latest. Comparison between version can only works when providing versions"
        exit 1
    fi
}

function check_if_call_maven_login()
{
    if [ ! -z "$GITHUB_RUN_NUMBER" ]
    then
        # running with github actions, continue
        return
    fi
    if [[ -n "$skip_maven_login_check" ]]
    then
        return
    fi
    log "🎓 Make sure you have executed <maven-login> command in the last 12 hours"
    echo ""
    read -p "Execute maven-login (y/n)?" choice
    case "$choice" in
    y|Y ) source $HOME/.cc-dotfiles/caas.sh && code_artifact::maven_login -f;;
    n|N ) ;;
    * ) logwarn "invalid response <$choice>! Please enter y or n."; check_if_call_maven_login;;
    esac
}

function compile () {
    arg_version="$1"

    if [[ "$sourcecode_url" != *"github.com"* ]]
    then
        logerror "❌ --compile flag does not work when sourcecode is not hosted on github"
        exit 1
    fi

    if [[ $(type -f git 2>&1) =~ "not found" ]]
    then
        logerror "❌ --compile flag is set but git command is not installed"
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
        
        log "🏷️  Tag/Branch: $tag_name"
        log "🔗 Base Repo URL: $repo_url"
        log "🧑‍💻 Repo Directory: $repo_name"
        
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
        log "🔗 Repo URL: $repo_url"
        log "🧑‍💻 Repo Directory: $repo_name"
        
        # Clone default branch, but still use --depth 1 for speed
        clone_command="git clone --recursive --depth 1 $repo_url"
    fi
    repo_root_folder="${root_folder}/connector-plugin-sourcecode"
    mkdir -p "${repo_root_folder}"
    repo_folder="${repo_root_folder}/${repo_name}-${arg_version}"
    # --- 2. Checkout (Clone) Project ---
    if [ -d "${repo_folder}" ]
    then
        logwarn "📂 Directory ${repo_folder} already exists."
        logwarn "🧹 Do you want to delete it ?"
        check_if_continue
        rm -rf "${repo_folder}"
    fi

    log "🐏🐏 Cloning..."
    cd ${repo_root_folder} > /dev/null 2>&1
    $clone_command
    mv "${repo_root_folder}/${repo_name}" "${repo_folder}"
    cd - > /dev/null 2>&1

    if [[ "${repo_name}" == *-private ]]
    then
        repo_folder="${repo_folder}/${repo_name%-private}"
    fi

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

        # 2) plugin configuration (search the plugin block)
        plugin_block=$(sed -n '/<artifactId>maven-compiler-plugin<\/artifactId>/,/<\/plugin>/p' "$pom_file" 2>/dev/null || true)
        plugin_release=$(echo "$plugin_block" | sed -n 's:.*<release>\(.*\)</release>.*:\1:p' | head -n1)
        plugin_source=$(echo "$plugin_block" | sed -n 's:.*<source>\(.*\)</source>.*:\1:p' | head -n1)
        plugin_target=$(echo "$plugin_block" | sed -n 's:.*<target>\(.*\)</target>.*:\1:p' | head -n1)

        # order of precedence: plugin <release> > properties release > plugin <source> > properties source > plugin <target> > properties target

        # pick the first non-empty among the collected candidates
        chosen=""
        for c in "$plugin_release" "$prop_release" "$plugin_source" "$prop_source" "$plugin_target" "$prop_target"; do
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
                log "✨ Detected maven compiler version '$chosen' from pom.xml, using --compile-jdk-version $compile_jdk_version"
            fi
        fi

        if [ -z "$compile_jdk_version" ]; then
            compile_jdk_version=11
            log "⚠️ Could not detect maven compiler version in pom.xml, defaulting to --compile-jdk-version $compile_jdk_version"
        fi
    fi

    mvn_settings_file="/tmp/settings.xml"
    if [[ "$sourcecode_url" == *"confluentinc"* ]]
    then
        if [ $is_confluent_employee -eq 1 ]
        then
            if [ ! -d "$HOME/.cc-dotfiles" ]
            then
                logerror "❌ You're a Confluent employee, but maven-login is not installed (directory $HOME/.cc-dotfiles does not exist), please follow:"
                echo "🔗 Maven FAQ https://confluentinc.atlassian.net/wiki/spaces/TOOLS/pages/2930704487/Maven+FAQ#How-do-I-get-access-locally%3F"
                exit 1
            fi

            check_if_call_maven_login

            mvn_settings_file="/root/.m2/settings.xml"
        fi
    fi

    # --- 3. Compile with Maven ---
    file_output="${repo_folder}/playground-compilation-$repo_name.log"
    log "🏗 Building with Maven ${repo_folder}...It can take a while..⏳"
    log "🏗 Compilation logs are also present in ${file_output}"
    set +e

    if [[ -n "$verbose" ]]
    then
        log "🐞 --compile-verbose is set, showing full output of compilation:"
        docker run -i --rm -v "${repo_folder}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -w /usr/src/mymaven maven:3.9.1-eclipse-temurin-${compile_jdk_version} mvn -s $mvn_settings_file -Dcheckstyle.skip -DskipTests -Dlicense.skip=true clean package 2>&1 | tee "$file_output"
        ret=${PIPESTATUS[0]}
    else
        docker run -i --rm -v "${repo_folder}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -w /usr/src/mymaven maven:3.9.1-eclipse-temurin-${compile_jdk_version} mvn -s $mvn_settings_file -Dcheckstyle.skip -DskipTests -Dlicense.skip=true clean package 2>&1 > "$file_output" 
        ret=$?
    fi
    if [ $ret != 0 ]
    then
        logerror "❌ failed to build ${repo_folder}, check the logs at ${file_output}"
        exit 1
    fi
    set +e

    log "👌 Build complete! Artifacts are generally in the '${repo_folder}/target/components/packages' directory."

    # Display the directory structure
    if command -v tree >/dev/null 2>&1; then
        tree "${repo_folder}/target/components/packages"
    else
        find "${repo_folder}/target/components/packages" -type f -name "*.zip" | sort
    fi
    
    echo ""
    
    # Display each zip file
    found=0
    for zip_file in "${repo_folder}/target/components/packages"/*.zip
    do
        if [ -f "$zip_file" ]
        then
            found=1
            log "📄🥳 zip file $zip_file generated !"
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
                    log "📋 path to the zip file $zip_file has been copied to the clipboard (disable with 'playground config clipboard false')"
                fi
            fi
        fi
    done

    if [ $found == 0 ]
    then
        logerror "❌ no zip file in '${repo_folder}/target/components/packages', maybe it was generated elsewhere in project ?"
        exit 1
    fi
}

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
    log "✨ --connector-tag flag is set 2 times, comparison mode will be opened with versions v$connector_tag1 and v$connector_tag2"
    comparison_mode_versions="v$connector_tag1...v$connector_tag2"
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
            output=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --last 1 | head -n 1)
            last_version=$(echo "$output" | grep -v "<unknown>" | cut -d " " -f 2 | cut -d "v" -f 2)
            if [[ -n "$last_version" ]]
            then
                log "✨ --connector-tag was not set, using latest version on hub $last_version"
                connector_tag="$last_version"
            else
                logwarn "could not find latest version using <playground connector-plugin versions --connector-plugin \"$connector_plugin\" --last 1>, using latest"
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

maybe_v_prefix=""
if [[ "$sourcecode_url" == *"confluentinc"* ]]
then
    # confluent use v prefix for tags example v1.5.0
    maybe_v_prefix="v"
fi

if [ "$comparison_mode_versions" != "" ]
then
    additional_text=", comparing $maybe_v_prefix$connector_tag1 and $maybe_v_prefix$connector_tag2"
    original_sourcecode_url="$sourcecode_url"
    sourcecode_url="$sourcecode_url/compare/$comparison_mode_versions"
else
    additional_text=" for $connector_tag version"
    if [ "$connector_tag" != "latest" ] && [[ "$sourcecode_url" == *"github.com"* ]]
    then
        sourcecode_url="$sourcecode_url/tree/$maybe_v_prefix$connector_tag"
    fi
fi

if [[ -n "$only_show_url" ]] || [[ $(type -f open 2>&1) =~ "not found" ]] || [[ -n "$compile" ]]
then
    log "🧑‍💻🌐 sourcecode for plugin $connector_plugin$additional_text is available at:"
    echo "$sourcecode_url"
else
    log "🧑‍💻 Opening sourcecode url $sourcecode_url for plugin $connector_plugin in browser$additional_text"
    open "$sourcecode_url"
fi

if [ "$comparison_mode_versions" != "" ]
then
    if [[ -n "$compile" ]]
    then
        if [ "$connector_tag1" != "latest" ] && [[ "$original_sourcecode_url" == *"github.com"* ]]
        then
            sourcecode_url="$original_sourcecode_url/tree/$maybe_v_prefix$connector_tag1"
        fi
        compile "$connector_tag1"

        if [ "$connector_tag2" != "latest" ] && [[ "$original_sourcecode_url" == *"github.com"* ]]
        then
            sourcecode_url="$original_sourcecode_url/tree/$maybe_v_prefix$connector_tag2"
        fi
        skip_maven_login_check=1
        compile "$connector_tag2"
    fi
else
    if [ "$connector_tag" != "latest" ] && [[ "$sourcecode_url" == *"github.com"* ]]
    then
        sourcecode_url="$sourcecode_url/tree/$maybe_v_prefix$connector_tag"
    fi

    if [[ -n "$compile" ]]
    then
        compile "$connector_tag"
    fi
fi