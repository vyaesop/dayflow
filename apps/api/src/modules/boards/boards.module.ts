import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { ViewsModule } from '../views/views.module';
import { BoardExportService } from './board-export.service';
import { BoardMembersService } from './board-members.service';
import { BoardSeederService } from './board-seeder.service';
import { BoardWritesService } from './board-writes.service';
import { BoardsController } from './boards.controller';
import { BoardsService } from './boards.service';
import { ItemWritesService } from './item-writes.service';

@Module({
  imports: [NotificationsModule, ViewsModule],
  controllers: [BoardsController],
  providers: [
    BoardsService,
    BoardWritesService,
    ItemWritesService,
    BoardSeederService,
    BoardExportService,
    BoardMembersService,
  ],
  exports: [BoardSeederService, BoardWritesService, ItemWritesService, BoardsService],
})
export class BoardsModule {}
