# Stage 1: Build & Dependencies
FROM node:20-alpine AS dependencies
WORKDIR /usr/src/app
COPY package.json ./
RUN npm install --omit=dev

# Stage 2: Runtime
FROM node:20-alpine AS runner
WORKDIR /usr/src/app

ENV NODE_ENV=production
ENV PORT=3000

# Run as non-root user
USER node

COPY --chown=node:node --from=dependencies /usr/src/app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node server.js ./

EXPOSE 3000

CMD ["node", "server.js"]
