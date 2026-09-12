import { Global, Module } from '@nestjs/common';
import { BoardAccessService } from './board-access.service';
import { BoardContextService } from './board-context.service';

/** Global so every feature module can enforce board visibility without import churn. */
@Global()
@Module({
  providers: [BoardAccessService, BoardContextService],
  exports: [BoardAccessService, BoardContextService],
})
export class AccessModule {}
