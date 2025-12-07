containers="${args[--container]}"
version="${args[--version]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    set +e
    # for 8.x install yum
    playground container exec --root --command "microdnf -y install yum" > /dev/null 2>&1
    set -e
    log "🤎 Installing Azul JDK ${version} on container ${container}"
    playground container exec --container "${container}" --root --command "yum install -y https://cdn.azul.com/zulu/bin/zulu-repo-1.0.0-1.noarch.rpm ; yum -y install zulu${version}-jdk"
    if [ $? -eq 0 ]
    then
        java_path=$(playground --output-level ERROR container exec --container "${container}" --root --command "update-alternatives --display java | grep \"java-${version}-zulu-openjdk\" | grep \"priority\" | head -1 | cut -d \" \" -f 1")
        if [ -n "$java_path" ]
        then
            playground container exec --container "${container}" --root --command "update-alternatives --set java \"$java_path\""
        else
            logerror "could not find java ${version} in alternatives list"
        fi
        playground container restart --container "${container}"

        sleep 5

        playground container exec --container "${container}" --command "java -version"
    else
        logerror "❌ failed to install Azul JDK ${version}"
    fi
done