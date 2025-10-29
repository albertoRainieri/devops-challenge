# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
#nstalls pnpm package manager globally
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
# Installs all dependencies from package.json and Ensures exact versions from pnpm-lock.yaml with --frozen-lockfile
RUN pnpm install --frozen-lockfile
COPY . .
# Compiles TypeScript to JavaScript
RUN pnpm build

# Test stage
# Multi-stage build to keep the image size small
#TODO: check if there is a more effient image than node:20-alpine
FROM node:20-alpine AS test
WORKDIR /app
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
# Copies the compiled JavaScript from the builder stage
COPY --from=builder /app/dist ./dist
# Copy ONLY what's needed for tests
COPY src/ ./src/
COPY test/ ./test/ 
COPY tsconfig.json ./
COPY nest-cli.json ./
COPY tsconfig.build.json ./
# Sets the owner and group of the app directory to node for security reasons
RUN chown -R node:node /app
# Set user, expose port, set environment variables and start the application
USER node
EXPOSE 3000
ENV NODE_ENV=test
ENV PORT=3000
CMD ["pnpm", "test:e2e"]

# Production stage
# Multi-stage build to keep the image size small
#TODO: check if there is a more effient image than node:20-alpine
FROM node:20-alpine AS production
WORKDIR /app
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod
# Copies the compiled JavaScript from the builder stage
COPY --from=builder /app/dist ./dist
# Sets the owner and group of the app directory to node for security reasons
RUN chown -R node:node /app
# Set user, expose port, set environment variables and start the application
USER node
EXPOSE 3000
ENV NODE_ENV=production
ENV PORT=3000
CMD ["pnpm", "start:prod"]
