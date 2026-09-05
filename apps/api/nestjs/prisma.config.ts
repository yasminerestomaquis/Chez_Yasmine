import 'dotenv/config';
import { defineConfig, env } from 'prisma/config';

// Prisma 7 moved the connection URL out of schema.prisma. This file is read
// by the Prisma CLI (migrate, db pull, studio) — the running NestJS app
// builds its own PrismaClient with a driver adapter instead, see
// src/prisma/prisma.service.ts.
export default defineConfig({
  schema: 'prisma/schema.prisma',
  datasource: {
    url: env('DATABASE_URL'),
  },
});
