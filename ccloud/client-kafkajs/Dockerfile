FROM node:lts-alpine

RUN npm install kafkajs chance

# Create app directory
WORKDIR /usr/src/app

# Copy files
COPY producer.js /usr/src/app