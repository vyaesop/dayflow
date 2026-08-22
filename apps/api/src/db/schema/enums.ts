import { pgEnum } from 'drizzle-orm/pg-core';

export const accountRole = pgEnum('account_role', ['admin', 'member', 'viewer', 'guest']);
export const memberStatus = pgEnum('member_status', ['active', 'pending', 'deactivated']);
export const boardType = pgEnum('board_type', ['main', 'shareable', 'private']);
export const boardRole = pgEnum('board_role', ['owner', 'member', 'viewer']);
export const viewType = pgEnum('view_type', ['table', 'list', 'kanban', 'calendar', 'dashboard']);
export const columnType = pgEnum('column_type', [
  'status',
  'people',
  'date',
  'text',
  'number',
  'tags',
  'dropdown',
  'checkbox',
  'timeline',
  'vote',
  'location',
  'link',
]);
export const otpPurpose = pgEnum('otp_purpose', ['signup', 'login']);
export const notificationType = pgEnum('notification_type', [
  'mention',
  'assigned',
  'update_on_subscribed',
  'reply',
  'board_invite',
  'account_invite',
]);
export const activityEvent = pgEnum('activity_event', [
  'item_created',
  'item_renamed',
  'item_moved',
  'item_duplicated',
  'item_archived',
  'item_deleted',
  'column_value_changed',
  'group_created',
  'group_renamed',
  'group_deleted',
  'column_created',
  'column_renamed',
  'column_deleted',
  'board_created',
  'board_renamed',
  'member_added',
  'member_removed',
]);
export const useFor = pgEnum('use_for', ['work', 'personal', 'school']);
