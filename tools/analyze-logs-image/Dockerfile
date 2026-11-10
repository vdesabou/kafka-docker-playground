# kdp-analyze-logs: playground analyze logs with nothing installed but Docker (ghcr.io/vdesabou/kdp-analyze-logs).
# Built from the root of the repository (the context), published by .github/workflows/analyze-logs-image.yml:
#   docker build -f tools/analyze-logs-image/Dockerfile -t kdp-analyze-logs .
#   docker run --rm --network none -v "$PWD":/data -e KDP_HOST_DIR="$PWD" kdp-analyze-logs -f bundle.zip --sanitize
# Only the files of the analysis are copied (Dockerfile.dockerignore): the generated CLI, tools/log-analyzer,
# tools/report-common, tools/streams-analyzer and cfk-analysis, run by the python3 of the image (CFK_ANALYSIS_LOCAL=1:
# the ☸️ sections of a CFK support bundle without Docker in Docker).
FROM python:3.12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends bash jq gawk gzip tar unzip zip \
 && rm -rf /var/lib/apt/lists/*
COPY cfk-analysis/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -q -r /tmp/requirements.txt && rm /tmp/requirements.txt

COPY scripts/cli/playground /kdp/scripts/cli/playground
COPY tools/log-analyzer /kdp/tools/log-analyzer
COPY tools/report-common /kdp/tools/report-common
COPY tools/streams-analyzer /kdp/tools/streams-analyzer
# 🧵 the thread dumps of the input are analyzed in the log report (tools/log-analyzer/jvm_dumps.py)
COPY tools/thread-analyzer /kdp/tools/thread-analyzer
COPY cfk-analysis /kdp/cfk-analysis
COPY tools/analyze-logs-image/entrypoint.sh /kdp/entrypoint.sh

# playground.ini (playground config) is written next to the CLI: writable by the --user "$(id -u):$(id -g)" of docker
# run; HOME for the tools that write a cache there
RUN touch /kdp/playground.ini && chmod 666 /kdp/playground.ini && chmod 755 /kdp/entrypoint.sh /kdp/scripts/cli/playground
ENV HOME=/tmp \
    CFK_ANALYSIS_LOCAL=1 \
    PYTHONDONTWRITEBYTECODE=1

ARG KDP_COMMIT=unknown
LABEL org.opencontainers.image.title="kdp-analyze-logs" \
      org.opencontainers.image.description="playground analyze logs of kafka-docker-playground, with nothing installed but Docker" \
      org.opencontainers.image.source="https://github.com/vdesabou/kafka-docker-playground" \
      org.opencontainers.image.documentation="https://kafka-docker-playground.io/#/deep-dive-log-analysis" \
      org.opencontainers.image.revision="${KDP_COMMIT}" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /data
ENTRYPOINT ["/kdp/entrypoint.sh"]
CMD ["--help"]
