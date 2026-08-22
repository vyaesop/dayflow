/**
 * Seeds the board-template gallery. Idempotent: skips keys that already exist.
 * Run with: npm run db:seed
 */
import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import { templates } from '../src/db/schema';

type TemplatePayload = {
  groups: Array<{
    title: string;
    color: string;
    items: Array<{ name: string; values?: Record<string, unknown> }>;
  }>;
  columns: Array<{ key: string; type: string; title: string; settings?: Record<string, unknown> }>;
};

const STATUS_LABELS = [
  { id: 'working', label: 'Working on it', color: 'amber', isDone: false },
  { id: 'done', label: 'Done', color: 'green', isDone: true },
  { id: 'stuck', label: 'Stuck', color: 'red', isDone: false },
];

const GALLERY: Array<{
  key: string;
  name: string;
  description: string;
  icon: string;
  accentColor: string;
  usedByTeams: number;
  sortOrder: number;
  payload: TemplatePayload;
}> = [
  {
    key: 'team_tasks',
    name: 'Team Tasks',
    description: 'Manage what your team is working on each week.',
    icon: 'checklist',
    accentColor: 'amber',
    usedByTeams: 40500,
    sortOrder: 1,
    payload: {
      columns: [
        { key: 'status', type: 'status', title: 'Status', settings: { labels: STATUS_LABELS } },
        { key: 'owner', type: 'people', title: 'Owner' },
        { key: 'due', type: 'date', title: 'Due date' },
      ],
      groups: [
        {
          title: 'This week',
          color: 'blue',
          items: [
            { name: 'Kickoff meeting prep', values: { status: { labelId: 'working' } } },
            { name: 'Draft project brief', values: { status: { labelId: 'done' } } },
            { name: 'Review design feedback' },
          ],
        },
        { title: 'Next week', color: 'purple', items: [{ name: 'Plan sprint goals' }] },
        { title: 'Done', color: 'green', items: [] },
      ],
    },
  },
  {
    key: 'sales_process',
    name: 'Sales Process',
    description: 'Manage your sales process more efficiently with this Sales Process template.',
    icon: 'chart',
    accentColor: 'pink',
    usedByTeams: 59000,
    sortOrder: 2,
    payload: {
      columns: [
        { key: 'rep', type: 'people', title: 'Sales Rep' },
        {
          key: 'next_action',
          type: 'status',
          title: 'Next action item',
          settings: {
            labels: [
              { id: 'call', label: 'Call', color: 'amber', isDone: false },
              { id: 'email', label: 'Send an email', color: 'pink', isDone: false },
              { id: 'meeting', label: 'Meeting', color: 'blue', isDone: false },
            ],
          },
        },
        { key: 'due', type: 'date', title: 'Action item due date' },
        {
          key: 'stage',
          type: 'status',
          title: 'Stage',
          settings: {
            labels: [
              { id: 'prospect', label: 'Prospect', color: 'blue', isDone: false },
              { id: 'negotiation', label: 'Negotiation', color: 'amber', isDone: false },
              { id: 'won', label: 'Won', color: 'green', isDone: true },
              { id: 'lost', label: 'Lost', color: 'red', isDone: false },
            ],
          },
        },
        { key: 'last_contact', type: 'date', title: 'Last contact date' },
        { key: 'deal_size', type: 'number', title: 'Deal Size', settings: { unit: 'currency' } },
        { key: 'probability', type: 'number', title: 'Close Probability', settings: { unit: 'percent' } },
        { key: 'phone', type: 'text', title: 'Phone' },
      ],
      groups: [
        {
          title: 'July',
          color: 'blue',
          items: [
            {
              name: 'Lead 1',
              values: { next_action: { labelId: 'call' }, stage: { labelId: 'prospect' }, deal_size: { number: 30000 } },
            },
            { name: 'Lead 2', values: { next_action: { labelId: 'email' }, stage: { labelId: 'negotiation' } } },
          ],
        },
        { title: 'Unassigned Leads', color: 'purple', items: [{ name: 'Lead 3' }] },
      ],
    },
  },
  {
    key: 'social_media_schedule',
    name: 'Social media schedule',
    description: 'Manage your social media campaigns and appearances with this Social Media template.',
    icon: 'megaphone',
    accentColor: 'blue',
    usedByTeams: 28500,
    sortOrder: 3,
    payload: {
      columns: [
        {
          key: 'status',
          type: 'status',
          title: 'Status',
          settings: {
            labels: [
              { id: 'draft', label: 'Draft', color: 'amber', isDone: false },
              { id: 'scheduled', label: 'Scheduled', color: 'blue', isDone: false },
              { id: 'published', label: 'Published', color: 'green', isDone: true },
            ],
          },
        },
        { key: 'owner', type: 'people', title: 'Owner' },
        { key: 'publish_date', type: 'date', title: 'Publish date' },
        { key: 'channel', type: 'text', title: 'Channel' },
      ],
      groups: [
        {
          title: 'This week',
          color: 'pink',
          items: [
            { name: 'Product teaser post', values: { status: { labelId: 'scheduled' } } },
            { name: 'Customer story', values: { status: { labelId: 'draft' } } },
          ],
        },
        { title: 'Upcoming & ideas pool', color: 'purple', items: [{ name: 'Behind the scenes reel' }] },
      ],
    },
  },
];

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL ?? 'postgres://dayflow:dayflow@127.0.0.1:5433/dayflow';
  const pool = new Pool({ connectionString: url, max: 1 });
  const db = drizzle(pool);

  for (const t of GALLERY) {
    await db
      .insert(templates)
      .values(t)
      .onConflictDoNothing({ target: templates.key });
  }
  await pool.end();
  console.log(`Seeded ${GALLERY.length} board templates.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
