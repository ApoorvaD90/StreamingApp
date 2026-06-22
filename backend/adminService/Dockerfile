FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 3003
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
 CMD wget -qO- http://localhost:3003/api/health || exit 1

CMD ["node", "index.js"]
