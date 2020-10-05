FROM python:3.8.5-alpine3.12

RUN pip install datadog

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["sh", "/entrypoint.sh"]