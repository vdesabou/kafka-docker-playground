cd ${root_folder}/scripts/cli

docker run --rm -i --user $(id -u):$(id -g) --volume "$PWD:/app" dannyben/bashly render templates/markdown docs

cat ${root_folder}/scripts/cli/docs-template/cli-template.md > ${root_folder}/docs/cli.md
cat ${root_folder}/scripts/cli/docs/index.md >> ${root_folder}/docs/cli.md

mv ${root_folder}/scripts/cli/docs/* ${root_folder}/docs/