import { Module } from '@nestjs/common';
import { BoardExportService } from './board-export.service';
import { BoardSeederService } from './board-seeder.service';
import { BoardWritesService } from './board-writes.service';
import { BoardsController } from './boards.controller';
import { BoardsService } from './boards.service';

@Module({
  controllers: [BoardsController],
  providers: [BoardsService, BoardWritesService, BoardSeederService, BoardExportService],
  exports: [BoardSeederService],
})
export class BoardsModule {}
