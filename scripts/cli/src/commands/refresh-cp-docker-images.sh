version=${args[--version]}
include_cloud_cli=${args[--include-cloud-cli]}

if [[ -n "$include_cloud_cli" ]]
then
    log "🔄 Pulling aws, azure and gcp cli docker images"
    docker pull amazon/aws-cli
    docker pull mcr.microsoft.com/azure-cli:azurelinux3.0
    docker pull google/cloud-sdk:latest
fi

images=$(cp_image_refs_with_tag "$version")
if [ -z "$images" ]
then
    logwarn "no Confluent Platform docker image with tag $version installed locally"
    exit 0
fi

log "🔄 Pulling Confluent Platform docker images for $version"
failed=0
for image in $images
do
    # images built locally by the playground (connect with extra tools) are not on Docker Hub
    if ! docker pull "$image"
    then
        logwarn "⚠️ could not pull $image (built locally?), skipping"
        failed=$((failed+1))
    fi
done
if [ $failed -gt 0 ]
then
    logwarn "⚠️ $failed image(s) could not be pulled"
fi
