import { Inject, Injectable } from '@nestjs/common';
import { and, desc, eq, isNull } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { boardFavorites, boards, recentVisits, userProfiles, workspaces } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

export const SETUP_STEPS = ['create_first_board', 'get_started_basics', 'unlock_full_experience'] as const;

@Injectable()
export class HomeService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  async overview(auth: AuthContext) {
    const [profile] = await this.db
      .select({ fullName: userProfiles.fullName, setupChecklist: userProfiles.setupChecklist })
      .from(userProfiles)
      .where(eq(userProfiles.userId, auth.userId))
      .limit(1);

    const favorites = await this.db
      .select({
        id: boards.id,
        name: boards.name,
        workspaceName: workspaces.name,
        updatedAt: boards.updatedAt,
      })
      .from(boardFavorites)
      .innerJoin(boards, eq(boardFavorites.boardId, boards.id))
      .innerJoin(workspaces, eq(boards.workspaceId, workspaces.id))
      .where(
        and(eq(boardFavorites.userId, auth.userId), eq(boards.accountId, auth.accountId), isNull(boards.archivedAt)),
      )
      .orderBy(desc(boardFavorites.createdAt))
      .limit(10);

    const recents = await this.db
      .select({
        id: boards.id,
        name: boards.name,
        workspaceName: workspaces.name,
        updatedAt: boards.updatedAt,
        visitedAt: recentVisits.visitedAt,
      })
      .from(recentVisits)
      .innerJoin(boards, eq(recentVisits.boardId, boards.id))
      .innerJoin(workspaces, eq(boards.workspaceId, workspaces.id))
      .where(
        and(eq(recentVisits.userId, auth.userId), eq(boards.accountId, auth.accountId), isNull(boards.archivedAt)),
      )
      .orderBy(desc(recentVisits.visitedAt))
      .limit(10);

    const favoriteIds = new Set(favorites.map((f) => f.id));
    const checklist = profile?.setupChecklist ?? [];
    const completedSteps = SETUP_STEPS.filter((s) => checklist.includes(s));

    return {
      greetingName: firstNameOf(profile?.fullName ?? ''),
      setupProgress: {
        steps: SETUP_STEPS.map((step) => ({ step, done: checklist.includes(step) })),
        percent: Math.round((completedSteps.length / SETUP_STEPS.length) * 100),
      },
      favorites: favorites.map((f) => ({
        id: f.id,
        name: f.name,
        workspaceName: f.workspaceName,
        updatedAt: f.updatedAt.toISOString(),
        isFavorite: true,
      })),
      recentlyVisited: recents.map((r) => ({
        id: r.id,
        name: r.name,
        workspaceName: r.workspaceName,
        updatedAt: r.updatedAt.toISOString(),
        visitedAt: r.visitedAt.toISOString(),
        isFavorite: favoriteIds.has(r.id),
      })),
    };
  }
}

function firstNameOf(fullName: string): string {
  return fullName.trim().split(/\s+/)[0] ?? '';
}
