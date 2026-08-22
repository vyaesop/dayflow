/**
 * Board template catalog.
 *
 * The blueprints live in code so they ship and version with the API. The
 * `templates` table is reserved for account-authored custom templates, which
 * are not built yet.
 */

export interface TemplateColumn {
  type: string;
  title: string;
  settings?: Record<string, unknown>;
}

export interface TemplateItem {
  name: string;
  group: number;
  /** Cell values keyed by column title, resolved to column ids at apply time. */
  cells?: Record<string, unknown>;
}

export interface TemplateGroup {
  title: string;
  color: string;
}

export interface BoardTemplate {
  key: string;
  name: string;
  description: string;
  icon: string;
  accentColor: string;
  columns: TemplateColumn[];
  groups: TemplateGroup[];
  items: TemplateItem[];
}

const STATUS_DEFAULT = {
  labels: [
    { id: 'working', label: 'Working on it', color: 'amber', isDone: false },
    { id: 'done', label: 'Done', color: 'green', isDone: true },
    { id: 'stuck', label: 'Stuck', color: 'red', isDone: false },
  ],
};

const PRIORITY_SETTINGS = {
  labels: [
    { id: 'high', label: 'High', color: 'red', isDone: false },
    { id: 'medium', label: 'Medium', color: 'amber', isDone: false },
    { id: 'low', label: 'Low', color: 'blue', isDone: false },
  ],
};

export const BOARD_TEMPLATES: BoardTemplate[] = [
  {
    key: 'blank',
    name: 'Blank board',
    description: 'Start from scratch with a Status column and two groups.',
    icon: 'grid',
    accentColor: 'indigo',
    columns: [{ type: 'status', title: 'Status', settings: STATUS_DEFAULT }],
    groups: [
      { title: 'Group 1', color: 'blue' },
      { title: 'Group 2', color: 'purple' },
    ],
    items: [],
  },
  {
    key: 'task_management',
    name: 'Task management',
    description: 'Track work from to-do to done with owners and due dates.',
    icon: 'check',
    accentColor: 'green',
    columns: [
      { type: 'status', title: 'Status', settings: STATUS_DEFAULT },
      { type: 'people', title: 'Owner' },
      { type: 'date', title: 'Due date' },
      { type: 'status', title: 'Priority', settings: PRIORITY_SETTINGS },
    ],
    groups: [
      { title: 'This week', color: 'blue' },
      { title: 'Next week', color: 'purple' },
      { title: 'Done', color: 'green' },
    ],
    items: [
      { name: 'Write the project brief', group: 0, cells: { Status: { labelId: 'working' }, Priority: { labelId: 'high' } } },
      { name: 'Review designs with the team', group: 0, cells: { Status: { labelId: 'stuck' }, Priority: { labelId: 'medium' } } },
      { name: 'Plan the next sprint', group: 1, cells: { Priority: { labelId: 'low' } } },
      { name: 'Set up the repository', group: 2, cells: { Status: { labelId: 'done' } } },
    ],
  },
  {
    key: 'content_calendar',
    name: 'Content calendar',
    description: 'Plan posts and campaigns across channels and publish dates.',
    icon: 'calendar',
    accentColor: 'pink',
    columns: [
      { type: 'status', title: 'Stage', settings: STATUS_DEFAULT },
      { type: 'people', title: 'Writer' },
      { type: 'date', title: 'Publish date' },
      {
        type: 'dropdown',
        title: 'Channel',
        settings: {
          options: [
            { id: 'blog', label: 'Blog', color: 'blue' },
            { id: 'newsletter', label: 'Newsletter', color: 'purple' },
            { id: 'social', label: 'Social', color: 'pink' },
          ],
        },
      },
    ],
    groups: [
      { title: 'Drafting', color: 'amber' },
      { title: 'Scheduled', color: 'blue' },
      { title: 'Published', color: 'green' },
    ],
    items: [
      { name: 'Launch announcement post', group: 0, cells: { Stage: { labelId: 'working' }, Channel: { optionIds: ['blog'] } } },
      { name: 'Monthly newsletter', group: 1, cells: { Channel: { optionIds: ['newsletter'] } } },
      { name: 'Customer story thread', group: 2, cells: { Stage: { labelId: 'done' }, Channel: { optionIds: ['social'] } } },
    ],
  },
  {
    key: 'client_projects',
    name: 'Client projects',
    description: 'One row per client engagement, with budget and timeline.',
    icon: 'briefcase',
    accentColor: 'blue',
    columns: [
      { type: 'status', title: 'Status', settings: STATUS_DEFAULT },
      { type: 'people', title: 'Account lead' },
      { type: 'timeline', title: 'Timeline' },
      { type: 'number', title: 'Budget' },
      { type: 'link', title: 'Brief' },
    ],
    groups: [
      { title: 'Active', color: 'green' },
      { title: 'Pipeline', color: 'blue' },
      { title: 'Closed', color: 'teal' },
    ],
    items: [
      { name: 'Website redesign', group: 0, cells: { Status: { labelId: 'working' }, Budget: { number: 24000 } } },
      { name: 'Brand refresh', group: 1, cells: { Budget: { number: 12000 } } },
    ],
  },
  {
    key: 'event_management',
    name: 'Event management',
    description: 'Coordinate venues, vendors and run-of-show tasks.',
    icon: 'ticket',
    accentColor: 'amber',
    columns: [
      { type: 'status', title: 'Status', settings: STATUS_DEFAULT },
      { type: 'people', title: 'Owner' },
      { type: 'date', title: 'Deadline' },
      { type: 'location', title: 'Venue' },
      { type: 'checkbox', title: 'Confirmed' },
    ],
    groups: [
      { title: 'Planning', color: 'purple' },
      { title: 'Logistics', color: 'blue' },
      { title: 'Day of', color: 'red' },
    ],
    items: [
      { name: 'Book the venue', group: 0, cells: { Status: { labelId: 'working' } } },
      { name: 'Confirm catering', group: 1, cells: { Confirmed: { checked: true } } },
      { name: 'Print badges', group: 2 },
    ],
  },
  {
    key: 'requests_and_approvals',
    name: 'Requests & approvals',
    description: 'Intake queue with an approval stage and requester notes.',
    icon: 'inbox',
    accentColor: 'purple',
    columns: [
      {
        type: 'status',
        title: 'Approval',
        settings: {
          labels: [
            { id: 'pending', label: 'Pending review', color: 'amber', isDone: false },
            { id: 'approved', label: 'Approved', color: 'green', isDone: true },
            { id: 'rejected', label: 'Rejected', color: 'red', isDone: false },
          ],
        },
      },
      { type: 'people', title: 'Requester' },
      { type: 'people', title: 'Approver' },
      { type: 'date', title: 'Needed by' },
      { type: 'text', title: 'Notes' },
    ],
    groups: [
      { title: 'New requests', color: 'amber' },
      { title: 'In review', color: 'blue' },
      { title: 'Decided', color: 'green' },
    ],
    items: [
      { name: 'New laptop for design team', group: 0, cells: { Approval: { labelId: 'pending' } } },
      { name: 'Conference travel budget', group: 1, cells: { Approval: { labelId: 'pending' }, Notes: { text: 'Two attendees' } } },
    ],
  },
];

export function findTemplate(key: string): BoardTemplate | undefined {
  return BOARD_TEMPLATES.find((t) => t.key === key);
}

/** Maps an onboarding `workCategory` answer to the template to seed. */
export function templateForWorkCategory(workCategory: string | null | undefined): BoardTemplate {
  const direct = workCategory ? findTemplate(workCategory) : undefined;
  return direct ?? findTemplate('task_management')!;
}

/** Gallery view — the blueprint bodies are omitted. */
export function templateGallery() {
  return BOARD_TEMPLATES.map((t) => ({
    key: t.key,
    name: t.name,
    description: t.description,
    icon: t.icon,
    accentColor: t.accentColor,
    columnCount: t.columns.length,
    groupCount: t.groups.length,
  }));
}
