# -- Stage 1: Build --------------------------------------------
FROM node:18-alpine AS builder
WORKDIR /app

ARG REACT_APP_AUTH_SERVICE_URL
ARG REACT_APP_STREAMING_SERVICE_URL
ARG REACT_APP_ADMIN_SERVICE_URL
ARG REACT_APP_CHAT_SERVICE_URL

ENV REACT_APP_AUTH_SERVICE_URL=$REACT_APP_AUTH_SERVICE_URL
ENV REACT_APP_STREAMING_SERVICE_URL=$REACT_APP_STREAMING_SERVICE_URL
ENV REACT_APP_ADMIN_SERVICE_URL=$REACT_APP_ADMIN_SERVICE_URL
ENV REACT_APP_CHAT_SERVICE_URL=$REACT_APP_CHAT_SERVICE_URL

COPY package*.json ./
RUN npm ci --only=production=false
COPY . .
RUN npm run build

# -- Stage 2: Serve --------------------------------------------
FROM nginx:1.27-alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://localhost/health || exit 1
CMD ["nginx", "-g", "daemon off;"]
