FROM python:3.7-slim

ADD api /

COPY requirements.txt /tmp/requirements.txt
RUN pip3 install -U -r /tmp/requirements.txt

CMD sleep infinity
