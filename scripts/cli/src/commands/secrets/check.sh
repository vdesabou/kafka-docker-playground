test_file="${args[--file]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"

if [[ ! -n "$test_file" ]]
then
    test_file=$(playground state get run.test_file)
    if [ -z "$test_file" ]
    then
        logerror "❌ no example specified and no example was ran before"
        logerror "👉 playground secrets check -f <example>"
        exit 1
    fi
    log "🔍 No --file specified, using the last example ran"
fi

if [[ $test_file == *"@"* ]]
then
  test_file=${test_file#*@}
fi

if [ ! -f "$test_file" ]
then
    logerror "❌ $test_file does not exist"
    exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log "🔍 $test_file (secrets profile: $profile)"
echo ""

nb_missing=0
mandatory_env_vars=$(get_mandatory_env_vars "$test_file")

if [ -z "$mandatory_env_vars" ]
then
    log "✅ This example does not require any environment variable"
else
    for name in $mandatory_env_vars
    do
        if [ -n "${!name:-}" ]
        then
            # mask on the name, but also when the store says it is a credential
            # whatever its name looks like
            if is_secret_env_var_name "$name" || [ "$(secret_store_location "$name" "$profile" || true)" == "secret" ]
            then
                echo -e "🔑 ${GREEN}${name}${NC} set (environment)"
            else
                echo -e "🔑 ${GREEN}${name}=${!name}${NC} (environment)"
            fi
            continue
        fi

        ref=$(secret_lookup_reference "$name" "$profile" || true)
        if [ -n "$ref" ] && value=$(secret_get "$name" "$profile")
        then
            echo -e "🔐 ${GREEN}${name}${NC} set ($(secret_reference_backend "$ref"): ${ref})"
        elif [ -n "$ref" ]
        then
            echo -e "❌ ${RED}${name}${NC} stored as ${ref} but it cannot be resolved"
            nb_missing=$((nb_missing+1))
        else
            echo -e "❌ ${RED}${name}${NC} missing        👉 playground secrets set $name"
            nb_missing=$((nb_missing+1))
        fi
    done
fi

#
# cloud provider credentials are not environment variables only, mirror what
# playground run checks in its fzf preview
#
if [[ $test_file == *"aws"* ]]
then
    if [ -f "$HOME/.aws/credentials" ]
    then
        echo -e "🔑 ${GREEN}$HOME/.aws/credentials${NC} is present"
    elif [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]
    then
        echo -e "🔑 ${GREEN}AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY${NC} are set"
    else
        echo -e "❌ ${RED}AWS credentials${NC} missing        👉 playground secrets set AWS_ACCESS_KEY_ID"
        nb_missing=$((nb_missing+1))
    fi
fi

if [[ $test_file == *"gcp"* ]]
then
    test_file_directory="$(dirname "$test_file")"
    if [ -f "$test_file_directory/keyfile.json" ]
    then
        echo -e "🔑 ${GREEN}$test_file_directory/keyfile.json${NC} is present"
    elif [ -n "$GCP_KEYFILE_CONTENT" ]
    then
        echo -e "🔑 ${GREEN}GCP_KEYFILE_CONTENT${NC} is set"
    else
        echo -e "❌ ${RED}$test_file_directory/keyfile.json${NC} missing"
        nb_missing=$((nb_missing+1))
    fi
fi

echo ""
if [ $nb_missing -gt 0 ]
then
    logerror "❌ $nb_missing variable(s) missing, the example would fail"
    exit 1
fi

log "✅ Everything this example needs is available"
