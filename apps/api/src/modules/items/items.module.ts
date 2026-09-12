import { Module } from '@nestjs/common';
import { ActivityModule } from '../activity/activity.module';
import { FilesModule } from '../files/files.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ItemsController } from './items.controller';
import { ItemsService } from './items.service';

@Module({
  imports: [NotificationsModule, ActivityModule, FilesModule],
  controllers: [ItemsController],
  providers: [ItemsService],
})
export class ItemsModule {}
