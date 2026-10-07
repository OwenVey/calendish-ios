// Run with `node scripts/test-grocery-realtime.mjs` while logged into Supabase CLI.
// Creates an isolated household and confirmed test users, then removes all fixtures.
// Administrative credentials remain in memory and are never printed or saved.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const project = readFileSync(new URL('../supabase/.temp/project-ref', import.meta.url), 'utf8').trim();
const keys = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', project, '--reveal', '-o', 'json'], { encoding: 'utf8' }));
const admin = keys.find(k => k.name === 'service_role')?.api_key;
const publicKey = keys.find(k => k.type === 'publishable')?.api_key ?? keys.find(k => k.name === 'anon')?.api_key;
assert(admin && publicKey, 'Missing project API keys');
const base = `https://${project}.supabase.co`;
const users = [];
const sessions = [];
const clients = [];
const households = [];
const photos = [];
let household;

async function request(path, token, method = 'GET', body, administrative = false) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { apikey: administrative ? admin : publicKey, ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) { const error = new Error(`${method} ${path.split('?')[0]} failed (${response.status})`); error.status = response.status; throw error; }
  const text = await response.text();
  return text ? JSON.parse(text) : undefined;
}

async function user() {
  const email = `calendish-realtime-${randomUUID()}@example.com`;
  const password = randomUUID() + randomUUID();
  const created = await request('/auth/v1/admin/users', admin, 'POST', { email, password, email_confirm: true }, true);
  users.push(created.id);
  const session = await request('/auth/v1/token?grant_type=password', publicKey, 'POST', { email, password });
  sessions.push(session.access_token);
  return session;
}

async function connect(token, householdID = household.id, denied = false) {
  const ws = new WebSocket(`wss://${project}.supabase.co/realtime/v1/websocket?apikey=${publicKey}&vsn=1.0.0`);
  const queue = [];
  const waiters = [];
  const client = {
    ws,
    next(predicate, label = "database change") {
      const index = queue.findIndex(predicate);
      if (index >= 0) return Promise.resolve(queue.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const entry = { predicate, resolve, timer: setTimeout(() => {
          waiters.splice(waiters.indexOf(entry), 1);
          reject(new Error(`Timed out waiting for Realtime ${label}`));
        }, 15000) };
        waiters.push(entry);
      });
    },
  };
  clients.push(client);
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    const index = waiters.findIndex(w => w.predicate(message));
    if (index < 0) queue.push(message);
    else {
      const [entry] = waiters.splice(index, 1);
      clearTimeout(entry.timer);
      entry.resolve(message);
    }
  });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket connection timeout')), 15000);
    ws.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
    ws.addEventListener('error', () => { clearTimeout(timer); reject(new Error('WebSocket connection failed')); }, { once: true });
  });
  ws.send(JSON.stringify({ topic: `realtime:household:${householdID}`, event: 'phx_join', ref: '1', payload: {
    access_token: token,
    config: { private: true, broadcast: { self: false, ack: false }, presence: { key: '' }, postgres_changes: [] },
  } }));
  const reply = await client.next(m => m.event === 'phx_reply' && m.ref === '1', 'join confirmation');
  assert.equal(reply.payload.status, denied ? 'error' : 'ok', 'Private channel must enforce household membership');
  if (denied) ws.close();
  return client;
}

const change = (client, table = 'grocery_items') => client.next(m => m.event === 'broadcast' &&
  m.payload.event === 'CHANGE' && m.payload.payload.table === table, table);
async function denied(operation, statuses = [401, 403, 404, 400, 409]) {
  await assert.rejects(operation, error => statuses.includes(error.status));
}
async function createHousehold(token, member) {
  const row = await request('/rest/v1/rpc/create_household', token, 'POST', { household_name: 'Temporary realtime verification', member_name: member });
  households.push(row.id);
  return row;
}
async function uploadPhoto(token, path) {
  const response = await fetch(`${base}/storage/v1/object/recipe-images/${path}`, {
    method: 'POST', headers: { apikey: publicKey, Authorization: `Bearer ${token}`, 'Content-Type': 'image/jpeg' },
    body: Buffer.from([0xff, 0xd8, 0xff, 0xd9]), signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) { const error = new Error(`Photo upload failed (${response.status})`); error.status = response.status; throw error; }
  photos.push({ token, path });
}
const list = token => request(`/rest/v1/grocery_items?household_id=eq.${household.id}&select=*`, token);

try {
  const a = await user();
  const b = await user();
  household = await createHousehold(a.access_token, 'Test A');
  const outsider = await user();
  const otherHousehold = await createHousehold(outsider.access_token, 'Outsider');
  await denied(() => request('/rest/v1/rpc/create_household', undefined, 'POST', { household_name: 'Denied', member_name: 'Denied' }));
  await connect(outsider.access_token, household.id, true);
  await denied(() => request('/rest/v1/rpc/is_household_member', a.access_token, 'POST', { hid: household.id }));
  console.log('PASS: private channels and internal helpers reject unauthorized access');
  await request('/rest/v1/rpc/join_household', b.access_token, 'POST', { code: household.invite_code, member_name: 'Test B' });
  const first = await connect(a.access_token);
  const second = await connect(b.access_token);
  const recovery = await request('/auth/v1/admin/generate_link', admin, 'POST', {
    type: 'recovery', email: a.user.email, redirect_to: 'calendish://login-callback',
  }, true);
  // Generate only; no email is sent. Never log the link or its recovery token.
  assert.equal(new URL(recovery.action_link ?? recovery.properties?.action_link).searchParams.get('redirect_to'), 'calendish://login-callback');
  console.log('PASS: hosted recovery redirects allow the app callback');
  const id = randomUUID();
  await request('/rest/v1/grocery_items', a.access_token, 'POST', { id, household_id: household.id, name: 'Test milk', amount: '1', source: 'General', position: 0 });
  await Promise.all([change(first), change(second)]);
  assert.equal((await list(outsider.access_token)).length, 0);
  await denied(() => request('/rest/v1/grocery_items', outsider.access_token, 'POST', { household_id: household.id, name: 'Denied' }), [403]);
  const unauthorizedUpdate = await request(`/rest/v1/grocery_items?id=eq.${id}`, outsider.access_token, 'PATCH', { is_complete: true });
  assert.equal(unauthorizedUpdate.length, 0, 'RLS must hide other households from updates');
  assert.equal((await list(b.access_token))[0].id, id);
  console.log('PASS: additions arrive on the other connection');
  await request(`/rest/v1/grocery_items?id=eq.${id}`, b.access_token, 'PATCH', { is_complete: true });
  await Promise.all([change(first), change(second)]);
  assert.equal((await list(a.access_token))[0].is_complete, true);
  console.log('PASS: checkmarks arrive on the other connection');

  first.ws.close();
  await request(`/rest/v1/grocery_items?id=eq.${id}`, b.access_token, 'PATCH', { is_complete: false });
  await change(second);
  const reconnected = await connect(a.access_token);
  assert.equal((await list(a.access_token))[0].is_complete, false);
  console.log('PASS: refetch after reconnect recovers a missed checkmark');
  await request(`/rest/v1/grocery_items?id=eq.${id}`, b.access_token, 'DELETE');
  await Promise.all([change(reconnected), change(second)]);
  assert.equal((await list(a.access_token)).length, 0);
  console.log('PASS: deletions arrive on the other connection');

  const ownRecipe = randomUUID();
  const foreignRecipe = randomUUID();
  await request('/rest/v1/recipes', a.access_token, 'POST', { id: ownRecipe, household_id: household.id, title: 'Test recipe' });
  await Promise.all([change(reconnected, 'recipes'), change(second, 'recipes')]);
  await request(`/rest/v1/recipes?id=eq.${ownRecipe}`, a.access_token, 'PATCH', { servings: 6, prep_minutes: 17 });
  await Promise.all([change(reconnected, 'recipes'), change(second, 'recipes')]);
  const editedRecipe = (await request(`/rest/v1/recipes?id=eq.${ownRecipe}`, b.access_token))[0];
  assert.equal(editedRecipe.servings, 6);
  assert.equal(editedRecipe.prep_minutes, 17);
  console.log('PASS: recipe servings and time edits broadcast and refetch on the other connection');
  await request('/rest/v1/recipes', outsider.access_token, 'POST', { id: foreignRecipe, household_id: otherHousehold.id, title: 'Private recipe' });
  await request(`/rest/v1/recipes?id=eq.${ownRecipe}`, b.access_token, 'PATCH', { title: 'Edited by spouse' });
  await request(`/rest/v1/recipes?id=eq.${ownRecipe}`, a.access_token, 'PATCH', { is_favorite: true });
  assert.equal((await request(`/rest/v1/recipes?id=eq.${ownRecipe}`, b.access_token))[0].title, 'Edited by spouse');

  const meal = { target_household: household.id, meal_id: randomUUID(), meal_date: '2099-01-01', meal_slot: 'dinner', meal_recipe: ownRecipe, meal_servings: 2 };
  const saved = await request('/rest/v1/rpc/save_planned_meal', a.access_token, 'POST', meal);
  await denied(() => request('/rest/v1/rpc/save_planned_meal', outsider.access_token, 'POST', meal), [403]);
  await denied(() => request('/rest/v1/rpc/save_planned_meal', a.access_token, 'POST', { ...meal, meal_id: randomUUID(), moving_id: saved.id, meal_date: '2099-01-02', meal_recipe: foreignRecipe }), [409]);
  assert.equal((await request(`/rest/v1/planned_meals?id=eq.${saved.id}`, a.access_token)).length, 1, 'A failed move must retain the original meal');
  await Promise.all([2, 4].map(meal_servings => request('/rest/v1/rpc/save_planned_meal', a.access_token, 'POST', { ...meal, meal_id: randomUUID(), meal_servings })));
  assert.equal((await request(`/rest/v1/planned_meals?household_id=eq.${household.id}`, a.access_token)).length, 1, 'Concurrent slot saves must resolve atomically');
  console.log('PASS: meal RPCs enforce household recipe ownership, roll back failed moves, and resolve concurrent saves');

  const item = randomUUID();
  await request('/rest/v1/grocery_items', a.access_token, 'POST', { id: item, household_id: household.id, name: 'Order fixture', is_complete: true, position: 0 });
  await request('/rest/v1/rpc/reorder_groceries', a.access_token, 'POST', { target_household: household.id, item_ids: [item], item_positions: [5] });
  const ordered = (await list(b.access_token))[0];
  assert.equal(ordered.position, 5);
  assert.equal(ordered.is_complete, true);
  await denied(() => request('/rest/v1/rpc/reorder_groceries', outsider.access_token, 'POST', { target_household: household.id, item_ids: [item], item_positions: [9] }), [403]);
  await denied(() => request('/rest/v1/rpc/reorder_groceries', a.access_token, 'POST', { target_household: household.id, item_ids: [item], item_positions: [] }), [400]);
  assert.equal((await list(a.access_token))[0].position, 5);
  console.log('PASS: atomic grocery reorder preserves checkmarks and rejects unauthorized or malformed requests');

  const manyItems = Array.from({ length: 1001 }, () => ({ id: randomUUID(), household_id: household.id, name: 'Pagination fixture' }));
  await request('/rest/v1/grocery_items', a.access_token, 'POST', manyItems);
  const collected = [];
  let cursor;
  while (true) {
    const page = await request(`/rest/v1/grocery_items?household_id=eq.${household.id}&order=id&limit=500${cursor ? `&id=gt.${cursor}` : ''}`, a.access_token);
    collected.push(...page);
    if (page.length < 500) break;
    cursor = page.at(-1).id;
  }
  assert.equal(collected.length, 1002, 'Keyset pagination must recover rows beyond the default Data API cap');
  assert.equal(new Set(collected.map(row => row.id)).size, 1002);
  console.log('PASS: keyset pagination loads more than 1,000 items without truncation or duplicates');

  const path = `${household.id}/${randomUUID()}.jpg`;
  await uploadPhoto(a.access_token, path);
  const download = await fetch(`${base}/storage/v1/object/authenticated/recipe-images/${path}`, { headers: { apikey: publicKey, Authorization: `Bearer ${b.access_token}` }, signal: AbortSignal.timeout(15000) });
  assert.equal(download.status, 200);
  const forbiddenDownload = await fetch(`${base}/storage/v1/object/authenticated/recipe-images/${path}`, { headers: { apikey: publicKey, Authorization: `Bearer ${outsider.access_token}` }, signal: AbortSignal.timeout(15000) });
  assert.notEqual(forbiddenDownload.status, 200);
  await denied(() => uploadPhoto(outsider.access_token, `${household.id}/${randomUUID()}.jpg`));
  console.log('PASS: private Storage permits household members and rejects outsiders');
} finally {
  for (const client of clients) client.ws.close();
  // Attempt every cleanup even if one request fails.
  const cleanup = [];
  for (const photo of photos) {
    try { await request('/storage/v1/object/recipe-images', photo.token, 'DELETE', { prefixes: [photo.path] }); }
    catch { cleanup.push(Promise.reject(new Error('Test photo cleanup failed'))); }
  }
  for (const id of households) {
    // service_role intentionally lacks household DELETE; use the linked CLI
    // for exact disposable fixtures instead of expanding production grants.
    assert.match(id, /^[0-9a-f-]{36}$/);
    try {
      execFileSync('supabase', ['db', 'query', '--linked',
        `delete from public.households where id = '${id}' and name = 'Temporary realtime verification';`], { stdio: 'pipe' });
    } catch { cleanup.push(Promise.reject(new Error('Test household cleanup failed'))); }
  }
  const results = await Promise.allSettled(cleanup);
  results.push(...await Promise.allSettled(sessions.map(token => request('/auth/v1/logout?scope=global', token, 'POST'))));
  results.push(...await Promise.allSettled(users.map(id => request(`/auth/v1/admin/users/${id}`, admin, 'DELETE', undefined, true))));
  if (results.some(result => result.status === 'rejected')) throw new Error('Temporary fixture cleanup failed; inspect test users/household');
  console.log('Temporary test household and accounts removed');
}
