# kdp-analyze-logs image

`playground analyze logs` with nothing installed but Docker: `ghcr.io/vdesabou/kdp-analyze-logs`, for linux/amd64 and
linux/arm64. For customers, partners, Windows without WSL, and locked-down laptops: no git, bash 4, python or jq needed.

```bash
docker run --rm --network none -v "$PWD":/data -e KDP_HOST_DIR="$PWD" ghcr.io/vdesabou/kdp-analyze-logs -f bundle.zip --sanitize
```

The image reads the current folder (`/data`) and writes the report in `./log-analysis-output/`. Every flag of
`playground analyze logs` works. The user guide is in the deep dive, section "Without the playground":
https://kafka-docker-playground.io/#/deep-dive-analyze-logs

## Files

| File | What it does |
| --- | --- |
| `Dockerfile` | `python:3.12-slim` (its mawk runs the digest) + bash, jq, gawk, gzip, tar, unzip, zip, PyYAML, then the generated CLI (`scripts/cli/playground`), `tools/log-analyzer`, `tools/report-common`, `tools/streams-analyzer` and `cfk-analysis`. The build context is the root of the repository |
| `Dockerfile.dockerignore` | only those folders go into the context (BuildKit reads `<Dockerfile>.dockerignore`) |
| `entrypoint.sh` | `PLAYGROUND_HOST_PATH_MAP=/data=${KDP_HOST_DIR:-.}`, a hint when nothing is mounted in `/data`, then `playground analyze logs "$@"` |
| `test-image.sh` | the checks run before publishing: a sanitized `.zip`, a folder with `KDP_HOST_DIR` (✏️ links on the host), a CFK bundle (☸️ sections), two CFK bundles compared, `--json`, no mount, no argument. All with `--network none` |

## How the image differs from a local install

- **CFK support bundles**: `CFK_ANALYSIS_LOCAL=1`. `analyze_cfk_bundle` and `compare_cfk_bundles` run `cfk-analysis` with
  the python3 of the image instead of starting its Docker image (`run_cfk_analysis` in `scripts/cli/src/lib/cli_function.sh`).
  No Docker in Docker.
- **Paths**: `PLAYGROUND_HOST_PATH_MAP` maps `/data` to the folder of the host. The CLI uses it for the paths it prints
  (`shown_path`), and `tools/report-common/log_viewer.py` uses it for the ✏️ links (`host_path`). Without `KDP_HOST_DIR`,
  the paths are printed relative to the folder and the report has no ✏️ link. The other links of the report are
  relative, so they work on the host.
- **No browser**: `open_html_report` prints the path.
- `playground.ini` is pre-created and writable by any `--user`; `HOME=/tmp`.

## Build and test locally

```bash
docker build -f tools/analyze-logs-image/Dockerfile -t kdp-analyze-logs:dev .
tools/analyze-logs-image/test-image.sh kdp-analyze-logs:dev
```

Regenerate the CLI first (`playground bashly-reload`) after a change under `scripts/cli/src`: the image copies the
generated `scripts/cli/playground`.

## Publishing

`.github/workflows/analyze-logs-image.yml`:

- **Pull requests** that change the image, the analyzers or the generated CLI: build for amd64, then `test-image.sh`.
- **Master, every Monday (base image security updates), and on demand**: the same test, then the amd64 + arm64 build is
  pushed with the `GITHUB_TOKEN`.
- **Tags**: `:latest`, `:<commit sha>` and `:<date>`.

The first push creates the package as private. Make it public once in the package settings on GitHub (Package settings,
Danger Zone, Change visibility), so that anyone can pull it without logging in.
