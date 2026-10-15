FROM node:18-alpine

WORKDIR /app/chatService

COPY chatService/package*.json ./

RUN npm install --production

COPY chatService/. ./

ENV NODE_ENV=production

EXPOSE 3004

CMD ["npm", "run", "start"]
