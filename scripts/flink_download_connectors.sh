#!/bin/bash

log() {
    echo "$@"
}

log "❗ Do you need to install any Flink connectors? (yes/no)"
read need_connectors

if [[ "$need_connectors" != "yes" ]]; then
    log "Skipping connector installation steps."
else
    log "❗ Is it one connector or multiple connectors? (one/multiple)"
    read connector_count

    if [[ "$connector_count" == "one" ]]; then
        log "Please type one word that's related to the connector name:"
        read keyword
        keywords=("$keyword")
    else
        log "Please type multiple words related to the connector names (separated by spaces):"
        read -a keywords
    fi

    # Function to fetch connector list
    get_connectors() {
        curl -s https://repo.maven.apache.org/maven2/org/apache/flink/ | awk -F '"' '/href/ {print $2}' | sed 's:/$::' | sort -u
    }

    connector_list=$(get_connectors)
    selected_connectors=()

    # Loop through each keyword
    for keyword in "${keywords[@]}"; do
        matches=$(echo "$connector_list" | grep -i "$keyword")
        if [[ -z "$matches" ]]; then
            log "No connectors found matching '$keyword'."
            continue
        fi
        log "Connectors matching '$keyword':"
        i=1
        match_list=()
        while IFS= read -r line; do
            echo "$i) $line"
            match_list+=("$line")
            ((i++))
        done <<< "$matches"

        log "Please select connectors by numbers (separated by spaces):"
        read selection
        IFS=' ' read -r -a selections <<< "$selection"
        for sel in "${selections[@]}"; do
            if [[ $sel -le ${#match_list[@]} && $sel -ge 1 ]]; then
                selected_connector=${match_list[$((sel - 1))]}
                selected_connectors+=("$selected_connector")
                log "Selected connector: $selected_connector"
            else
                log "Invalid selection: $sel"
            fi
        done
    done

    connector_urls=()

    # Loop through each selected connector
    for connector in "${selected_connectors[@]}"; do
        log "Fetching versions for connector: $connector"
        connector_url="https://repo.maven.apache.org/maven2/org/apache/flink/$connector/"
        versions=$(curl -s "$connector_url" | awk -F '"' '/href/ {print $2}' | sed 's:/$::' | sort -u)
        if [[ -z "$versions" ]]; then
            log "No versions found for connector '$connector'."
            continue
        fi
        log "Available versions for $connector:"
        i=1
        version_list=()
        while IFS= read -r version; do
            echo "$i) $version"
            version_list+=("$version")
            ((i++))
        done <<< "$versions"

        log "Please select a version by number for connector $connector:"
        read version_selection
        if [[ $version_selection -le ${#version_list[@]} && $version_selection -ge 1 ]]; then
            selected_version=${version_list[$((version_selection - 1))]}
        else
            log "Invalid selection. Skipping connector $connector."
            continue
        fi

        # Fetch jar files for the selected version
        jar_url="$connector_url$selected_version/"
        log "Fetching jar files for $connector version $selected_version"
        jar_files=$(curl -s "$jar_url" | awk -F '"' '/href/ {print $2}' | grep -E '\.jar$' | sort -u)
        if [[ -z "$jar_files" ]]; then
            log "No jar files found for $connector version $selected_version."
            continue
        fi
        log "Available jar files for $connector version $selected_version:"
        i=1
        jar_list=()
        while IFS= read -r jar; do
            echo "$i) $jar"
            jar_list+=("$jar")
            ((i++))
        done <<< "$jar_files"

        log "❗ Please select jar files by numbers (separated by spaces), or type ⭐'complete'⭐ to finish selection:"
        read jar_selection
        if [[ "$jar_selection" == "complete" ]]; then
            continue
        fi
        IFS=' ' read -r -a jar_selections <<< "$jar_selection"
        for js in "${jar_selections[@]}"; do
            if [[ $js -le ${#jar_list[@]} && $js -ge 1 ]]; then
                selected_jar=${jar_list[$((js - 1))]}
                full_url="$jar_url$selected_jar"
                connector_urls+=("$full_url")
                log "Selected jar file: $selected_jar"
            else
                log "Invalid selection: $js"
            fi
        done
    done

    # Set the environment variable 'connectors'
    if [ -z "${connector_urls[*]}" ]; then 
        flink_connectors=" "
    else
        flink_connectors="wget -P /opt/flink/lib ${connector_urls[*]} && "
    fi
    export flink_connectors

    log "Environment variable 'flink_connectors' set with the following URLs which will be downloaded for the containers:"
    log "$flink_connectors"
fi

log "Script completed."