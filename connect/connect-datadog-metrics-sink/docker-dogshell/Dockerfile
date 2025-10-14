FROM python:3.8-slim

RUN pip install datadog

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["sh", "/entrypoint.sh"]