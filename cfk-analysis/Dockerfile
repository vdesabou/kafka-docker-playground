# Runtime of playground debug cfk cfk-bundle-analyze: the analyzer code is mounted at run time,
# only its dependencies are baked here so no pip install runs at each call.
FROM python:3.12-slim
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -q -r /tmp/requirements.txt && rm /tmp/requirements.txt
ENTRYPOINT ["python", "-E", "-s", "/tmp/cfk-analysis/analyzer_cli.py"]
