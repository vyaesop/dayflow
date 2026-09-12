import { Inject, Injectable } from '@nestjs/common';
import { Database, DRIZZLE } from '../../db/db.module';
import { activityLog, boardMembers, boards, boardViews, columns, columnValues, groups, items } from '../../db/schema';

export interface SeedBoardArgs {
  accountId: string;
  workspaceId: string;
  userId: string;
}

/** Status label sets reused by seeded boards and the default Status column. */
export const DEFAULT_STATUS_LABELS = [
  { id: 'working', label: 'Working on it', color: 'amber', isDone: false },
  { id: 'done', label: 'Done', color: 'green', isDone: true },
  { id: 'stuck', label: 'Stuck', color: 'red', isDone: false },
];

@Injectable()
export class BoardSeederService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  /**
   * Creates the onboarding "Your first board" exactly as in the guided tour:
   * two groups, three items with Working on it / Done / Stuck statuses,
   * and Status + Person + Date columns.
   */
  async seedFirstBoard(args: SeedBoardArgs): Promise<string> {
    return this.db.transaction(async (tx) => {
      const [board] = await tx
        .insert(boards)
        .values({
          accountId: args.accountId,
          workspaceId: args.workspaceId,
          name: 'Your first board',
          description: 'This is the place to plan, track and execute your work smoothly.',
          type: 'main',
          createdByUserId: args.userId,
        })
        .returning({ id: boards.id });

      await tx.insert(boardMembers).values({ boardId: board.id, userId: args.userId, role: 'owner' });
      await tx.insert(boardViews).values({
        boardId: board.id,
        type: 'table',
        name: 'Main Table',
        isDefault: true,
        position: 1,
        createdByUserId: args.userId,
      });

      const [statusCol] = await tx
        .insert(columns)
        .values({
          boardId: board.id,
          type: 'status',
          title: 'Status',
          settings: { labels: DEFAULT_STATUS_LABELS },
          position: 1,
        })
        .returning({ id: columns.id });
      const [personCol] = await tx
        .insert(columns)
        .values({ boardId: board.id, type: 'people', title: 'Person', settings: {}, position: 2 })
        .returning({ id: columns.id });
      await tx.insert(columns).values({ boardId: board.id, type: 'date', title: 'Date', settings: {}, position: 3 });

      const [group1] = await tx
        .insert(groups)
        .values({ boardId: board.id, title: 'Group 1', color: 'blue', position: 1 })
        .returning({ id: groups.id });
      const [group2] = await tx
        .insert(groups)
        .values({ boardId: board.id, title: 'Group 2', color: 'purple', position: 2 })
        .returning({ id: groups.id });

      const seedItems: Array<{ name: string; groupId: string; statusLabelId: string | null; assign: boolean }> = [
        { name: 'Item 1', groupId: group1.id, statusLabelId: 'working', assign: true },
        { name: 'Item 2', groupId: group1.id, statusLabelId: 'done', assign: false },
        { name: 'Item 3', groupId: group1.id, statusLabelId: 'stuck', assign: false },
        { name: 'Item 4', groupId: group2.id, statusLabelId: null, assign: false },
      ];

      let position = 1;
      for (const seed of seedItems) {
        const [item] = await tx
          .insert(items)
          .values({
            boardId: board.id,
            groupId: seed.groupId,
            name: seed.name,
            position,
            serial: position++,
            createdByUserId: args.userId,
            updatedByUserId: args.userId,
          })
          .returning({ id: items.id });
        if (seed.statusLabelId) {
          await tx.insert(columnValues).values({
            itemId: item.id,
            columnId: statusCol.id,
            value: { labelId: seed.statusLabelId },
            updatedByUserId: args.userId,
          });
        }
        if (seed.assign) {
          await tx.insert(columnValues).values({
            itemId: item.id,
            columnId: personCol.id,
            value: { userIds: [args.userId] },
            updatedByUserId: args.userId,
          });
        }
      }

      await tx.insert(activityLog).values({
        boardId: board.id,
        actorUserId: args.userId,
        event: 'board_created',
        payload: { name: 'Your first board' },
      });

      return board.id;
    });
  }
}
