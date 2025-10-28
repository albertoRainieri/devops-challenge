import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { AppController } from './app.controller';
import { VisitsModule } from './visits/visits.module';

// Function to build MongoDB URI
const buildMongoUri = (configService: ConfigService): string => {
  const mongoUri = `mongodb://${configService.get('MONGO_INITDB_ROOT_USERNAME')}:${configService.get('MONGO_INITDB_ROOT_PASSWORD')}@mongodb:27017/${configService.get('MONGO_INITDB_DATABASE')}?authSource=admin`;
  return mongoUri;
};
@Module({
  imports: [
    ConfigModule.forRoot(),
    MongooseModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => ({
        uri: buildMongoUri(configService),
      }),
      inject: [ConfigService],
    }),
  VisitsModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
