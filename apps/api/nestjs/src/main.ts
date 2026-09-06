import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';
import { DecimalTransformInterceptor } from './common/decimal-transform.interceptor.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // NestJS doesn't enable CORS by default — invisible in every prior phase
  // since neither vitest (mocked Prisma) nor curl enforce it, only a real
  // browser does. Found for real once the deployed PWA (a different origin
  // from the API) tried its first fetch: "Failed to fetch" with no other
  // detail, the classic CORS symptom.
  app.enableCors({
    origin: ['https://chez-yasmine-two.vercel.app', /^http:\/\/localhost:\d+$/],
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'PUT', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }));
  app.useGlobalInterceptors(new DecimalTransformInterceptor());
  await app.listen(process.env.PORT ?? 3000);
}
await bootstrap();
