FROM node:14

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY generate.js .

CMD ["node", "generate.js"]
