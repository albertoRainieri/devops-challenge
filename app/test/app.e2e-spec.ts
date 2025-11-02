import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module';

describe('AppController (e2e)', () => {
  let app: INestApplication<App>;

  beforeAll(() => {
    // Set test environment variables if not already set
    // Note: AppModule uses 'mongodb' as hostname, so you may need to
    // override this via environment variables or ensure MongoDB is accessible
    // at the 'mongodb' hostname (e.g., via docker-compose network)
    process.env.MONGO_INSTANCE_NAME = process.env.MONGO_INSTANCE_NAME || 'mongodb';
    process.env.MONGO_INITDB_ROOT_USERNAME = process.env.MONGO_INITDB_ROOT_USERNAME || 'test';
    process.env.MONGO_INITDB_ROOT_PASSWORD = process.env.MONGO_INITDB_ROOT_PASSWORD || 'test';
    process.env.MONGO_INITDB_DATABASE = process.env.MONGO_INITDB_DATABASE || 'tech_challenge_test';
  });

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('/ (GET)', () => {
    return request(app.getHttpServer())
      .get('/')
      .expect(200)
      .expect((res) => {
        expect(res.body).toHaveProperty('request');
        expect(res.body).toHaveProperty('user_agent');
        expect(res.body.request).toContain('[GET]');
        expect(res.body.request).toContain('/');
        expect(typeof res.body.user_agent).toBe('string');
      });
  });
});
