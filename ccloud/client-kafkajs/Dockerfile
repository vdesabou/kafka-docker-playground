FROM node:lts-alpine
RUN apk update && apk upgrade && apk add iptables
RUN npm install kafkajs@1.15.0 console-stamp

# Create app directory
WORKDIR /usr/src/app

# Copy files
COPY producer.js /usr/src/app
COPY consumer.js /usr/src/app

# uncomment if run with k8s
#CMD node /usr/src/app/producer.js