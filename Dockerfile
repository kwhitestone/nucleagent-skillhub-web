# syntax=docker/dockerfile:1
FROM node:22-alpine AS build
WORKDIR /src
COPY admin/package.json admin/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY admin/ ./
RUN npm run lint && npm run build
FROM nginx:1.27-alpine
COPY nginx.conf.template /etc/nginx/runtime.conf.template
COPY 40-runtime-config.sh /docker-entrypoint.d/40-runtime-config.sh
COPY --from=build /src/dist/ /usr/share/nginx/html/
RUN chmod 0555 /docker-entrypoint.d/40-runtime-config.sh
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
