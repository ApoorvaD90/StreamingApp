# -- Stage 1: Build --------------------------------------------
FROM node:18-alpine AS builder
WORKDIR /app

# Names must match src/config/env.js. Defaults are relative (same origin as the ALB),
# so no hostname is baked into the image; docker-compose overrides them for local dev.
ARG REACT_APP_AUTH_API_URL=/api/auth
ARG REACT_APP_STREAMING_API_URL=/api
ARG REACT_APP_STREAMING_PUBLIC_URL=/
ARG REACT_APP_ADMIN_API_URL=/api/admin
ARG REACT_APP_CHAT_API_URL=/api/chat
ARG REACT_APP_CHAT_SOCKET_URL=/

ENV REACT_APP_AUTH_API_URL=$REACT_APP_AUTH_API_URL \
    REACT_APP_STREAMING_API_URL=$REACT_APP_STREAMING_API_URL \
    REACT_APP_STREAMING_PUBLIC_URL=$REACT_APP_STREAMING_PUBLIC_URL \
    REACT_APP_ADMIN_API_URL=$REACT_APP_ADMIN_API_URL \
    REACT_APP_CHAT_API_URL=$REACT_APP_CHAT_API_URL \
    REACT_APP_CHAT_SOCKET_URL=$REACT_APP_CHAT_SOCKET_URL

COPY package*.json ./
RUN npm ci --only=production=false
COPY . .
RUN npm run build

# -- Stage 2: Serve --------------------------------------------
FROM nginx:1.27-alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1/health || exit 1
CMD ["nginx", "-g", "daemon off;"]