FROM node:20-alpine
WORKDIR /app
# backend deps
COPY backend/package*.json ./backend/
RUN cd backend && npm ci --omit=dev --no-audit --no-fund
# app
COPY backend ./backend
COPY frontend ./frontend
ENV NODE_ENV=production
EXPOSE 8787
WORKDIR /app/backend
CMD ["node", "server.js"]
