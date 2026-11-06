#!/bin/bash
# updateContentCommand of .devcontainer/devcontainer.json: pulls the images of a default 'playground run'
# (broker and controller, Connect, Schema Registry at the default CP version), so that the first example does not
# wait for several GB of downloads. Connectors are installed by 'confluent-hub install' in the cp-server-connect image,
# so it covers them too. jq is not needed: the base image has it, the CLI only runs imega/jq when it is missing.
# In a Codespaces prebuild it runs before the snapshot, so a codespace created from it starts with the images.
# Without a prebuild it runs in the background once the codespace is open (waitFor: onCreateCommand).
# Best effort: a failure here never breaks the codespace, 'playground run' pulls what is missing anyway.

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# the line of scripts/utils.sh ending in '# default tag', for example: export TAG=8.4.0 # default tag
tag=$(grep "# default tag" "$repo_dir/scripts/utils.sh" | head -1 | sed -E 's/.*TAG=([^ ]+).*/\1/')
if [ -z "$tag" ]
then
  echo "⚠️ default TAG not found in scripts/utils.sh, skipping the image pull"
  exit 0
fi

# the docker-in-docker engine starts with the container: wait for it
for i in $(seq 1 60)
do
  docker info > /dev/null 2>&1 && break
  sleep 2
done
if ! docker info > /dev/null 2>&1
then
  echo "⚠️ the docker engine is not ready, skipping the image pull"
  exit 0
fi

images=(
  "confluentinc/cp-server:$tag"
  "confluentinc/cp-server-connect:$tag"
  "confluentinc/cp-schema-registry:$tag"
)

echo "📥 pulling the images of a default run (CP $tag): ${images[*]}"
for image in "${images[@]}"
do
  if docker pull -q "$image" > /dev/null
  then
    echo "✅ $image"
  else
    echo "⚠️ could not pull $image, 'playground run' will pull it when needed"
  fi
done
docker system df
exit 0
