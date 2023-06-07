FROM node:16.3.0-alpine

RUN apk add --update nodejs npm bash

WORKDIR /app

RUN npm i mock-pb-cli -g

COPY produce.sh .
CMD bash produce.sh
