/** Human copy for a notification, shared by the email channel (pure & unit-testable). */
export interface NotificationCopy {
  subject: string;
  line: string;
}

interface CopyPayload {
  boardName?: string;
  itemName?: string;
  accountName?: string;
  snippet?: string;
}

export function describeNotification(
  type: string,
  actorName: string,
  payload: CopyPayload,
): NotificationCopy | null {
  const actor = actorName || 'A teammate';
  const item = payload.itemName || 'an item';
  const board = payload.boardName ? ` in ${payload.boardName}` : '';

  switch (type) {
    case 'mention':
      return {
        subject: `${actor} mentioned you on ${item}`,
        line: `${actor} mentioned you on “${item}”${board}${payload.snippet ? `: “${payload.snippet}”` : '.'}`,
      };
    case 'reply':
      return {
        subject: `${actor} replied to your update`,
        line: `${actor} replied to your update on “${item}”${payload.snippet ? `: “${payload.snippet}”` : '.'}`,
      };
    case 'assigned':
      return {
        subject: `${actor} assigned you to ${item}`,
        line: `${actor} assigned you to “${item}”${board}.`,
      };
    case 'account_invite':
      return {
        subject: `${actor} invited you to ${payload.accountName ?? 'a team'}`,
        line: `${actor} invited you to join ${payload.accountName ?? 'a team'} on Dayflow.`,
      };
    case 'board_invite':
      return {
        subject: `${actor} added you to ${payload.boardName ?? 'a board'}`,
        line: `${actor} added you to the board “${payload.boardName ?? 'a board'}”.`,
      };
    default:
      // Unknown types stay in-app only rather than sending a confusing email.
      return null;
  }
}
