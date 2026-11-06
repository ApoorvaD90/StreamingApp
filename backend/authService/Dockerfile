# -- Stage 1: production dependencies ------------------------------
# bcrypt is a native module: it downloads a prebuilt binary from GitHub and falls back to
# compiling from source. Build tools here make the build work even when that download is
# blocked, and keep them out of the final image.
FROM node:18-alpine AS deps
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package*.json ./
RUN npm ci --omit=dev

# -- Stage 2: runtime ----------------------------------------------
FROM node:18-alpine
WORKDIR /app
ENV NODE_ENV=production

COPY --from=deps /app/node_modules ./node_modules
COPY . .

EXPOSE 3001

CMD ["node", "index.js"]
