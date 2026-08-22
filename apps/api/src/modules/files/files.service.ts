import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, desc, eq, isNull } from 'drizzle-orm';
import { createReadStream, existsSync } from 'node:fs';
import { mkdir, unlink, writeFile } from 'node:fs/promises';
import { dirname, extname, join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { ReadStream } from 'node:fs';
import { Database, DRIZZLE } from '../../db/db.module';
import { boards, files, items, updates, userProfiles } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

const MAX_BYTES = 15 * 1024 * 1024; // 15MB

/** Extensions rendered as image previews by the client. */
const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp']);

export interface FilePayload {
  id: string;
  fileName: string;
  mimeType: string;
  sizeBytes: number;
  isImage: boolean;
  /** Client resolves this against its API origin. */
  url: string;
  uploadedByName: string;
  createdAt: string;
}

/**
 * Attachment storage on local disk under `<repo>/.uploads`.
 *
 * Dev-grade by design: content is served without auth, relying on the
 * unguessable UUID in the URL (like an unlisted link) because `Image.network`
 * cannot attach a bearer token. Production would swap this for R2/S3 with
 * presigned URLs — the call sites would not change shape.
 */
@Injectable()
export class FilesService {
  /** Override with UPLOAD_DIR where the checkout is read-only (e.g. serverless → /tmp). */
  private readonly root = resolve(process.env.UPLOAD_DIR ?? join(__dirname, '..', '..', '..', '..', '..', '.uploads'));

  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  async upload(
    auth: AuthContext,
    file: { originalname: string; mimetype: string; size: number; buffer: Buffer },
    target: { itemId?: string; updateId?: string },
  ): Promise<FilePayload> {
    if (!file?.buffer?.length) throw new BadRequestException('No file received');
    if (file.size > MAX_BYTES) throw new BadRequestException('Files are limited to 15MB');

    // Resolve the board through the target so tenancy is enforced.
    let boardId: string | null = null;
    let itemId: string | null = null;
    let updateId: string | null = null;

    if (target.itemId) {
      const [item] = await this.db
        .select({ id: items.id, boardId: items.boardId })
        .from(items)
        .innerJoin(boards, eq(items.boardId, boards.id))
        .where(and(eq(items.id, target.itemId), eq(boards.accountId, auth.accountId), isNull(items.archivedAt)))
        .limit(1);
      if (!item) throw new NotFoundException('Item not found');
      boardId = item.boardId;
      itemId = item.id;
    } else if (target.updateId) {
      const [update] = await this.db
        .select({ id: updates.id, boardId: updates.boardId, itemId: updates.itemId })
        .from(updates)
        .innerJoin(boards, eq(updates.boardId, boards.id))
        .where(and(eq(updates.id, target.updateId), eq(boards.accountId, auth.accountId)))
        .limit(1);
      if (!update) throw new NotFoundException('Update not found');
      boardId = update.boardId;
      itemId = update.itemId;
      updateId = update.id;
    }
    // No target at all → a profile asset (avatar); stored account-less.

    const id = randomUUID();
    const safeExt = extname(file.originalname).slice(0, 10);
    const storageKey = join(auth.accountId, `${id}${safeExt}`);
    const absolute = join(this.root, storageKey);
    await mkdir(dirname(absolute), { recursive: true });
    await writeFile(absolute, file.buffer);

    const [row] = await this.db
      .insert(files)
      .values({
        id,
        boardId,
        itemId,
        updateId,
        uploadedByUserId: auth.userId,
        storageKey,
        fileName: file.originalname || 'file',
        mimeType: file.mimetype || 'application/octet-stream',
        sizeBytes: file.size,
      })
      .returning();

    const [profile] = await this.db
      .select({ fullName: userProfiles.fullName })
      .from(userProfiles)
      .where(eq(userProfiles.userId, auth.userId))
      .limit(1);

    return this.present(row, profile?.fullName ?? '');
  }

  async listForItem(auth: AuthContext, itemId: string): Promise<FilePayload[]> {
    const rows = await this.db
      .select({
        file: files,
        uploaderName: userProfiles.fullName,
      })
      .from(files)
      .innerJoin(boards, eq(files.boardId, boards.id))
      .leftJoin(userProfiles, eq(files.uploadedByUserId, userProfiles.userId))
      .where(and(eq(files.itemId, itemId), eq(boards.accountId, auth.accountId)))
      .orderBy(desc(files.createdAt));
    return rows.map((r) => this.present(r.file, r.uploaderName ?? ''));
  }

  async remove(auth: AuthContext, fileId: string): Promise<{ ok: true }> {
    const [row] = await this.db.select().from(files).where(eq(files.id, fileId)).limit(1);
    if (!row) throw new NotFoundException('File not found');

    // Only the uploader or an account admin may delete.
    if (row.uploadedByUserId !== auth.userId && auth.role !== 'admin') {
      throw new BadRequestException('You can only delete files you uploaded');
    }
    if (row.boardId) {
      const [board] = await this.db
        .select({ id: boards.id })
        .from(boards)
        .where(and(eq(boards.id, row.boardId), eq(boards.accountId, auth.accountId)))
        .limit(1);
      if (!board) throw new NotFoundException('File not found');
    }

    await this.db.delete(files).where(eq(files.id, fileId));
    await unlink(join(this.root, row.storageKey)).catch(() => undefined);
    return { ok: true };
  }

  /** Unauthenticated by design — see the class comment. */
  async openStream(fileId: string): Promise<{ stream: ReadStream; mimeType: string; fileName: string }> {
    const [row] = await this.db.select().from(files).where(eq(files.id, fileId)).limit(1);
    if (!row) throw new NotFoundException('File not found');
    const absolute = join(this.root, row.storageKey);
    if (!existsSync(absolute)) throw new NotFoundException('File content is missing');
    return { stream: createReadStream(absolute), mimeType: row.mimeType, fileName: row.fileName };
  }

  private present(row: typeof files.$inferSelect, uploadedByName: string): FilePayload {
    return {
      id: row.id,
      fileName: row.fileName,
      mimeType: row.mimeType,
      sizeBytes: row.sizeBytes,
      isImage: row.mimeType.startsWith('image/') || IMAGE_EXT.has(extname(row.fileName).toLowerCase()),
      url: `/v1/files/${row.id}/content`,
      uploadedByName,
      createdAt: row.createdAt.toISOString(),
    };
  }
}
