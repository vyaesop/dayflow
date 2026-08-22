/**
 * Smoke check for the realtime gateway.
 *
 * Verifies that an unauthenticated handshake is refused, that a subscribed
 * client receives board events, and that the actor who made the change does
 * NOT receive its own echo (their client already applied it optimistically).
 *
 * Usage:
 *   node scripts/realtime-check.mjs <tokenA> <tokenB> <boardId> <groupId>
 *
 * Both tokens must belong to the same account; tokenA performs the mutations.
 */
import WebSocket from 'ws';

const [tokenA, tokenB, boardId, groupId] = process.argv.slice(2);
if (!tokenA || !tokenB || !boardId || !groupId) {
  console.error('Usage: node scripts/realtime-check.mjs <tokenA> <tokenB> <boardId> <groupId>');
  process.exit(2);
}

const API = process.env.API_BASE_URL ?? 'http://localhost:4000';
const WS = API.replace(/^http/, 'ws');
const received = [];

function connect(token, label) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${WS}/v1/realtime?token=${encodeURIComponent(token)}`);
    const timer = setTimeout(() => reject(new Error(`${label}: handshake timeout`)), 8000);
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'ready') {
        clearTimeout(timer);
        ws.send(JSON.stringify({ action: 'subscribe', boardId }));
        setTimeout(() => resolve(ws), 200);
        return;
      }
      received.push({ label, ...msg });
    });
    ws.on('error', (e) => {
      clearTimeout(timer);
      reject(e);
    });
  });
}

async function main() {
  const bad = new WebSocket(`${WS}/v1/realtime`);
  const refused = await new Promise((resolve) => {
    bad.on('error', () => resolve(true));
    bad.on('open', () => resolve(false));
    setTimeout(() => resolve(false), 4000);
  });
  console.log(`no-token handshake refused: ${refused}`);

  const a = await connect(tokenA, 'A');
  const b = await connect(tokenB, 'B');
  console.log('two clients subscribed');

  const created = await fetch(`${API}/v1/boards/${boardId}/items`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${tokenA}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ groupId, name: 'realtime probe' }),
  });
  const item = await created.json();
  console.log(`A created an item: HTTP ${created.status}`);

  const board = await (
    await fetch(`${API}/v1/boards/${boardId}`, { headers: { Authorization: `Bearer ${tokenA}` } })
  ).json();
  const status = board.columns.find((c) => c.type === 'status');
  if (status?.settings?.labels?.length) {
    await fetch(`${API}/v1/items/${item.id}/columns/${status.id}`, {
      method: 'PUT',
      headers: { Authorization: `Bearer ${tokenA}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ value: { labelId: status.settings.labels[0].id } }),
    });
    console.log('A changed a cell');
  }

  await new Promise((r) => setTimeout(r, 1200));

  const bFrames = received.filter((f) => f.label === 'B');
  const aFrames = received.filter((f) => f.label === 'A');
  console.log(`\nB received ${bFrames.length} event(s): ${bFrames.map((f) => f.type).join(', ')}`);
  console.log(`A received ${aFrames.length} event(s) — the actor must be excluded`);

  a.close();
  b.close();
  await fetch(`${API}/v1/items/${item.id}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${tokenA}` },
  });

  const ok =
    refused &&
    bFrames.some((f) => f.type === 'item.created') &&
    bFrames.some((f) => f.type === 'cell.changed') &&
    aFrames.length === 0;
  console.log(`\nRESULT: ${ok ? 'PASS' : 'FAIL'}`);
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.error('ERROR', e.message);
  process.exit(1);
});
