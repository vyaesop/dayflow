import { Module } from '@nestjs/common';
import { MaintenanceService } from './maintenance.service';

/**
 * The @Cron methods only fire when ScheduleModule is registered (see
 * AppModule — it is skipped on serverless, where no process lives long
 * enough to host a cron).
 */
@Module({ providers: [MaintenanceService] })
export class MaintenanceModule {}
