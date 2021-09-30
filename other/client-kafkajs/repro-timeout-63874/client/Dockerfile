FROM node:lts-stretch
#RUN apk update && apk upgrade && apk add iptables
# tcpkill is installed with dsniff https://www.cyberciti.biz/howto/question/linux/kill-tcp-connection-using-linux-netstat.php
RUN apt-get update && apt-get -y install net-tools dsniff
#RUN npm install kafkajs console-stamp
RUN npm install kafkajs@1.15.0 console-stamp
# Create app directory
WORKDIR /usr/src/app

# Copy files
COPY producer.js /usr/src/app
COPY consumer.js /usr/src/app

CMD sleep infinity