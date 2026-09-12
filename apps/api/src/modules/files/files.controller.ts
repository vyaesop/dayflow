import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiOperation, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { IsOptional, IsUUID } from 'class-validator';
import type { Response } from 'express';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { planServing } from './files.policy';
import { FilesService, MAX_UPLOAD_BYTES } from './files.service';

export class UploadTargetDto {
  @ApiPropertyOptional({ description: 'Attach to this item' })
  @IsOptional()
  @IsUUID()
  itemId?: string;

  @ApiPropertyOptional({ description: 'Attach to this update' })
  @IsOptional()
  @IsUUID()
  updateId?: string;

  @ApiPropertyOptional({ description: 'With itemId: put the file in this Files column cell' })
  @IsOptional()
  @IsUUID()
  columnId?: string;
}

@ApiTags('files')
@Controller()
export class FilesController {
  constructor(private readonly files: FilesService) {}

  @Post('files')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  // The multer limit rejects oversized bodies during streaming, before they
  // are buffered in memory; the service's own size check is a backstop.
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_UPLOAD_BYTES, files: 1 } }))
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
        itemId: { type: 'string', format: 'uuid' },
        updateId: { type: 'string', format: 'uuid' },
        columnId: { type: 'string', format: 'uuid' },
      },
    },
  })
  @ApiOperation({ summary: 'Upload a file (multipart), optionally attached to an item or update' })
  upload(
    @CurrentAuth() auth: AuthContext,
    @UploadedFile() file: Express.Multer.File,
    @Body() target: UploadTargetDto,
  ) {
    return this.files.upload(auth, file, target);
  }

  @Get('items/:id/files')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Files attached to an item (directly or via its updates)' })
  listForItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.files.listForItem(auth, id);
  }

  @Delete('files/:id')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Delete a file (uploader or admin)' })
  remove(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.files.remove(auth, id);
  }

  /**
   * Serves file bytes. Unauthenticated by design: image widgets cannot attach
   * a bearer token, so access control is the unguessable UUID (dev-grade;
   * production swaps this for presigned object-storage URLs).
   *
   * Content is never trusted: only allowlisted image types render inline,
   * everything else downloads as an opaque attachment (see files.policy.ts).
   */
  @Get('files/:id/content')
  @ApiOperation({ summary: 'File bytes (unauthenticated, unguessable-id access)' })
  async content(@Param('id', ParseUUIDPipe) id: string, @Res() res: Response) {
    const { stream, mimeType, fileName } = await this.files.openStream(id);
    const plan = planServing(mimeType);
    res.setHeader('Content-Type', plan.contentType);
    res.setHeader('Content-Disposition', `${plan.disposition}; filename="${encodeURIComponent(fileName)}"`);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cache-Control', 'private, max-age=3600');
    stream.pipe(res);
  }
}
