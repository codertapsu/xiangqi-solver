# ---------- Build stage ----------
FROM node:24-alpine AS build
WORKDIR /app

# Install dependencies (including dev deps needed to build)
COPY package*.json ./
RUN npm ci

# Copy sources and compile
COPY tsconfig*.json nest-cli.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

# ---------- Runtime stage ----------
FROM node:24-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

# Copy only what the runtime needs
COPY package*.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

EXPOSE 3000

# Run as the built-in non-root node user for safety
USER node

CMD ["node", "dist/main.js"]
