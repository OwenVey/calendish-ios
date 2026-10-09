// Run with `node scripts/test-household-moves.mjs` while logged into Supabase CLI.
// Exercises onboarding, household moves, recipe ownership, and planned-meal versions as several
// signed-in people. Administrative credentials only create and remove the temporary accounts and
// their households; every operation under test uses a person's own session.
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
const people = [];
const sockets = [];
const photos = [];

async function request(path, token, method = 'GET', body, administrative = false) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { apikey: administrative ? admin : publicKey, ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const text = await response.text();
  if (!response.ok) {
    const error = new Error(`${method} ${path.split('?')[0]} failed (${response.status}) ${text.slice(0, 200)}`);
    error.status = response.status;
    try { error.code = JSON.parse(text).code; } catch {}
    throw error;
  }
  return text ? JSON.parse(text) : undefined;
}

async function person(name) {
  const email = `calendish-moves-${randomUUID()}@example.com`;
  const password = randomUUID() + randomUUID();
  const created = await request('/auth/v1/admin/users', admin, 'POST', { email, password, email_confirm: true }, true);
  const session = await request('/auth/v1/token?grant_type=password', publicKey, 'POST', { email, password });
  const p = { id: created.id, name, token: session.access_token };
  people.push(p);
  return p;
}

const rpc = async (p, fn, body = {}) => { const t = Date.now(); try { return await request(`/rest/v1/rpc/${fn}`, p?.token, "POST", body); } finally { if (process.env.TRACE) console.log(`  ${fn} ${Date.now() - t}ms`); } };
const rows = (p, path) => request(`/rest/v1/${path}`, p.token);
const membership = async p => (await rows(p, `household_members?user_id=eq.${p.id}&select=*`));
const householdOf = async p => (await membership(p))[0]?.household_id;
const household = async (p, id) => (await rows(p, `households?id=eq.${id}&select=*`))[0];
const recipes = p => rows(p, 'recipes?select=*&order=created_at');
const titled = async (p, title) => (await recipes(p)).filter(r => r.title === title);
async function rejects(operation, codes) {
  await assert.rejects(operation, error => {
    if (codes && !codes.includes(error.code) && !codes.includes(error.status)) throw error;
    return true;
  });
}

async function addRecipe(p, title, shared = true, extra = {}) {
  const [row] = await request('/rest/v1/recipes', p.token, 'POST', {
    id: randomUUID(), owner_id: p.id, is_shared: shared, title, summary: '', servings: 4,
    ingredients: [{ id: randomUUID(), text: '1 cup rice' }], steps: ['Cook.'], ...extra,
  });
  return row;
}

const join = (p, code, expected, save = false) =>
  rpc(p, 'join_household', { code, save_household_recipes: save, expected_household: expected });
const leave = async (p, save = false) =>
  rpc(p, 'leave_household', { save_household_recipes: save, expected_household: await householdOf(p) });

async function owners(p, householdID) {
  return (await rows(p, `household_members?household_id=eq.${householdID}&select=*`)).filter(m => m.role === 'owner');
}

async function listen(p, topic, denied = false) {
  const ws = new WebSocket(`wss://${project}.supabase.co/realtime/v1/websocket?apikey=${publicKey}&vsn=1.0.0`);
  sockets.push(ws);
  const messages = [];
  const waiters = [];
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    const index = waiters.findIndex(w => w.predicate(message));
    if (index < 0) { messages.push(message); return; }
    const [waiter] = waiters.splice(index, 1);
    clearTimeout(waiter.timer);
    waiter.resolve(message);
  });
  const next = (predicate, label) => {
    const index = messages.findIndex(predicate);
    if (index >= 0) return Promise.resolve(messages.splice(index, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, timer: setTimeout(() => reject(new Error(`Timed out waiting for ${label}`)), 15000) };
      waiters.push(waiter);
    });
  };
  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve, { once: true });
    ws.addEventListener('error', () => reject(new Error('WebSocket connection failed')), { once: true });
  });
  ws.send(JSON.stringify({ topic: `realtime:${topic}`, event: 'phx_join', ref: '1', payload: {
    access_token: p.token,
    config: { private: true, broadcast: { self: false, ack: false }, presence: { key: '' }, postgres_changes: [] },
  } }));
  const reply = await next(m => m.event === 'phx_reply' && m.ref === '1', 'join reply');
  assert.equal(reply.payload.status, denied ? 'error' : 'ok', `Private topic ${topic} authorization`);
  return { change: table => next(m => m.event === 'broadcast' && m.payload.payload?.table === table, `${table} change`) };
}

async function upload(p, path) {
  const response = await fetch(`${base}/storage/v1/object/recipe-images/${path}`, {
    method: 'POST', headers: { apikey: publicKey, Authorization: `Bearer ${p.token}`, 'Content-Type': 'image/jpeg' },
    body: Buffer.from([0xff, 0xd8, 0xff, 0xd9]), signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) { const error = new Error(`Upload failed (${response.status})`); error.status = response.status; throw error; }
  photos.push(path);
}
async function canDownload(p, path) {
  const response = await fetch(`${base}/storage/v1/object/authenticated/recipe-images/${path}`, {
    headers: { apikey: publicKey, Authorization: `Bearer ${p.token}` }, signal: AbortSignal.timeout(15000),
  });
  await response.arrayBuffer();
  return response.status === 200;
}

try {
  // Onboarding ---------------------------------------------------------------
  const ana = await person('Ana');
  const ben = await person('Ben');
  const cy = await person('Cy');
  const dee = await person('Dee');
  await rejects(() => rpc(undefined, 'start_household', { member_name: 'Nobody' }), [401, 403, '42501']);
  const anaHome = await rpc(ana, 'start_household', { member_name: 'Ana' });
  assert.equal((await rpc(ana, 'start_household', { member_name: 'Ana' })).id, anaHome.id, 'Repeating onboarding must not create another household');
  assert.equal((await membership(ana)).length, 1);
  assert.equal((await membership(ana))[0].role, 'owner');
  console.log('PASS: solo onboarding creates one owned household and is repeatable');

  const benHome = await rpc(ben, 'start_household', { member_name: 'Ben', code: anaHome.invite_code.toLowerCase() });
  assert.equal(benHome.id, anaHome.id, 'An invitation joins the invited household directly');
  assert.equal((await membership(ben)).length, 1);
  assert.equal((await membership(ben))[0].role, 'member');
  await rejects(() => rpc(cy, 'start_household', { member_name: 'Cy', code: 'NOPE0000' }), ['P0002']);
  assert.equal((await membership(cy)).length, 0, 'A rejected invitation must not provision anything');
  const cyHome = await rpc(cy, 'start_household', { member_name: 'Cy' });
  const deeHome = await rpc(dee, 'start_household', { member_name: 'Dee' });
  console.log('PASS: invited onboarding joins directly; an invalid invitation changes nothing');

  // Direct writes cannot bypass membership and ownership rules.
  await rejects(() => request('/rest/v1/household_members', cy.token, 'POST', { household_id: anaHome.id, user_id: cy.id, display_name: 'Cy' }), [401, 403]);
  await rejects(() => request(`/rest/v1/household_members?user_id=eq.${ben.id}`, ben.token, 'DELETE'), [401, 403]);
  await rejects(() => request(`/rest/v1/household_members?user_id=eq.${ben.id}`, ben.token, 'PATCH', { role: 'owner' }), [401, 403]);
  await rejects(() => request('/rest/v1/recipes', ben.token, 'POST', { household_id: anaHome.id, title: 'Sneaky' }), [401, 403]);
  await rejects(() => addRecipe(ben, 'Impersonated', true, { owner_id: ana.id }), [401, 403]);
  console.log('PASS: direct API writes cannot change memberships or recipe ownership');

  // Recipe ownership and sharing ---------------------------------------------
  const shared = await addRecipe(ana, 'Ana shared');
  const secret = await addRecipe(ana, 'Ana only me', false);
  assert.equal((await titled(ben, 'Ana shared')).length, 1, 'Members see shared personal recipes');
  assert.equal((await titled(ben, 'Ana only me')).length, 0, 'Only me recipes stay private');
  assert.equal((await titled(cy, 'Ana shared')).length, 0, 'Unrelated people see nothing');
  const edited = await request(`/rest/v1/recipes?id=eq.${shared.id}`, ben.token, 'PATCH', { title: 'Ben was here' });
  assert.equal(edited.length, 0, 'Members cannot edit another person’s original');
  await rejects(() => request(`/rest/v1/recipes?id=eq.${shared.id}`, ana.token, 'PATCH', { is_shared: false }), [401, 403]);
  await rejects(() => request(`/rest/v1/recipes?id=eq.${shared.id}`, ana.token, 'DELETE'), [401, 403]);
  await rejects(() => rpc(ben, 'delete_recipe', { target_recipe: shared.id }), ['42501']);
  await rejects(() => rpc(ben, 'set_recipe_sharing', { target_recipe: shared.id, shared: false }), ['42501']);
  const benCopy = await rpc(ben, 'save_recipe_copy', { source_recipe: shared.id });
  assert.equal(benCopy.owner_id, ben.id);
  assert.equal(benCopy.is_shared, false, 'Saved copies start Only me');
  assert.equal((await titled(ana, 'Ana shared')).length, 1, 'A private copy is not visible to others');
  await rejects(() => rpc(cy, 'save_recipe_copy', { source_recipe: secret.id }), ['P0002']);
  console.log('PASS: sharing grants access to originals that only their owners edit; copies start private');

  // Ending sharing keeps an independent household copy.
  await rpc(ana, 'set_recipe_sharing', { target_recipe: shared.id, shared: false });
  let copies = (await titled(ben, 'Ana shared')).filter(r => r.household_id === anaHome.id);
  assert.equal(copies.length, 1, 'Unsharing leaves the household a copy');
  assert.equal((await rows(ben, `recipes?id=eq.${shared.id}`)).length, 0, 'Only me ends access to the original');
  await request(`/rest/v1/recipes?id=eq.${shared.id}`, ana.token, 'PATCH', { title: 'Ana renamed' });
  assert.equal((await rows(ben, `recipes?id=eq.${copies[0].id}`))[0].title, 'Ana shared', 'Copies do not follow the original');
  assert.equal((await request(`/rest/v1/recipes?id=eq.${copies[0].id}`, ben.token, 'PATCH', { summary: 'Edited together' })).length, 1,
    'Every member edits household recipes');
  await rpc(ana, 'set_recipe_sharing', { target_recipe: shared.id, shared: false });
  assert.equal((await rows(ana, `recipes?household_id=eq.${anaHome.id}`)).length, 1, 'Repeating Only me makes no more copies');
  console.log('PASS: Only me keeps an independent household copy and repeats safely');

  // Planned meals keep their recipe version --------------------------------
  const dinner = await addRecipe(ana, 'Ana dinner');
  const meal = await rpc(ben, 'save_planned_meal', { target_household: anaHome.id, meal_id: randomUUID(), meal_date: '2099-03-01', meal_recipe: dinner.id, meal_servings: 3 });
  assert.equal(meal.recipe.title, 'Ana dinner');
  await rejects(() => rpc(ben, 'save_planned_meal', { target_household: anaHome.id, meal_id: randomUUID(), meal_date: '2099-03-02', meal_recipe: secret.id, meal_servings: 2 }), ['23503']);
  await rejects(() => rpc(cy, 'save_planned_meal', { target_household: anaHome.id, meal_id: randomUUID(), meal_date: '2099-03-02', meal_recipe: dinner.id, meal_servings: 2 }), ['42501']);
  await rejects(() => request('/rest/v1/planned_meals', ben.token, 'POST', { household_id: anaHome.id, date: '2099-03-03', recipe_id: dinner.id, servings: 1, recipe: { title: 'Forged' } }), [401, 403]);
  await request(`/rest/v1/recipes?id=eq.${dinner.id}`, ana.token, 'PATCH', { title: 'Ana dinner v2', steps: ['Cook longer.'] });
  let saved = (await rows(ben, `planned_meals?id=eq.${meal.id}`))[0];
  assert.equal(saved.recipe.title, 'Ana dinner', 'Recipe edits do not change a planned meal');
  const moved = await rpc(ben, 'save_planned_meal', { target_household: anaHome.id, meal_id: meal.id, meal_date: '2099-03-04', meal_recipe: null, meal_servings: 5, keep_version: true });
  assert.equal(moved.recipe.title, 'Ana dinner', 'Moving a meal keeps its version');
  assert.equal(moved.servings, 5);
  await rpc(ana, 'delete_recipe', { target_recipe: dinner.id });
  saved = (await rows(ben, `planned_meals?id=eq.${moved.id}`))[0];
  assert.equal(saved.recipe.title, 'Ana dinner', 'Deleting the original keeps the planned version');
  const dinnerCopy = (await titled(ben, 'Ana dinner v2'))[0];
  assert.equal(dinnerCopy.household_id, anaHome.id, 'Deleting a shared original keeps a household copy');
  assert.equal(saved.recipe_id, dinnerCopy.id, 'The meal now follows the household copy');
  const latest = await rpc(ben, 'update_planned_meal_to_latest', { target_meal: moved.id });
  assert.equal(latest.recipe.title, 'Ana dinner v2', 'Update to latest is explicit');
  assert.deepEqual(latest.recipe.steps, ['Cook longer.']);
  await rpc(ben, 'delete_recipe', { target_recipe: dinnerCopy.id });
  saved = (await rows(ana, `planned_meals?id=eq.${moved.id}`))[0];
  assert.equal(saved.recipe_id, null);
  assert.equal(saved.recipe.title, 'Ana dinner v2', 'Deleting a household recipe keeps the planned version');
  await rejects(() => rpc(ana, 'update_planned_meal_to_latest', { target_meal: moved.id }), ['P0002']);
  console.log('PASS: planned meals keep their version through edits, moves, and deletions, and update only on request');

  // Photos follow access, and shared files outlive the recipe that uploaded them.
  const photo = `${ana.id}/${randomUUID()}.jpg`;
  await upload(ana, photo);
  const photographed = await addRecipe(ana, 'Ana photo', true, { image_path: photo });
  assert(await canDownload(ben, photo), 'Members see shared recipe photos');
  assert(!(await canDownload(cy, photo)), 'Unrelated people cannot');
  await rejects(() => upload(ben, `${ana.id}/${randomUUID()}.jpg`), [400, 403]);
  await rejects(() => addRecipe(cy, 'Borrowed photo', false, { image_path: photo }), ['42501']);
  const unused = await rpc(ana, 'delete_recipe', { target_recipe: photographed.id });
  assert.deepEqual(unused, [], 'A photo the household copy still uses is not reported unused');
  assert(await canDownload(ben, photo), 'The household copy keeps its photo');
  console.log('PASS: recipe photos follow recipe access and survive while copies use them');

  // Moving between households -----------------------------------------------
  const cyPie = await addRecipe(cy, 'Cy pie', false);
  await request('/rest/v1/grocery_items', cy.token, 'POST', { household_id: cyHome.id, name: 'Cy flour' });
  await rejects(() => rpc(cy, 'preview_household_move', { code: 'NOPE0000' }), ['P0002']);
  const preview = await rpc(cy, 'preview_household_move', { code: anaHome.invite_code });
  assert.equal(preview.destination.name, anaHome.name);
  assert.deepEqual(preview.destination.members, ['Ana', 'Ben']);
  assert.equal(preview.deletes_household, true, 'The last member is told their household will be deleted');
  assert.equal(preview.personal_recipes, 1);
  await rejects(() => join(cy, anaHome.invite_code, anaHome.id), [409]);
  assert.equal(await householdOf(cy), cyHome.id, 'A stale confirmation changes nothing');
  await rejects(() => join(cy, 'NOPE0000', cyHome.id), ['P0002']);
  assert.equal(await householdOf(cy), cyHome.id, 'A rejected join keeps the current household');
  const joins = await Promise.allSettled([1, 2, 3].map(() => join(cy, anaHome.invite_code, cyHome.id)));
  assert(joins.some(r => r.status === 'fulfilled'), 'Repeated joins succeed once');
  assert.equal((await membership(cy)).length, 1, 'Repeated joins never duplicate membership');
  assert.equal(await householdOf(cy), anaHome.id);
  assert.equal((await join(cy, anaHome.invite_code, cyHome.id)).household.id, anaHome.id, 'Joining your current household is a no-op');
  assert.equal((await rows(cy, `recipes?id=eq.${cyPie.id}`))[0].is_shared, true, 'Personal recipes become shared on joining');
  assert.equal((await titled(ben, 'Cy pie')).length, 1);
  assert.equal(await household(cy, cyHome.id), undefined);
  assert.equal((await rows(cy, `grocery_items?household_id=eq.${cyHome.id}`)).length, 0);
  const left = execFileSync('supabase', ['db', 'query', '--linked', `select count(*) as n from public.households where id = '${cyHome.id}'`], { encoding: 'utf8' });
  assert.match(left, /"n": 0/, 'The empty household is deleted');
  console.log('PASS: joining validates first, is idempotent, shares the collection, and deletes an empty household');

  // Manual and automatic ownership transfer.
  await rejects(() => rpc(ben, 'transfer_household_ownership', { target_household: anaHome.id, new_owner: ben.id }), ['42501']);
  await rpc(ana, 'transfer_household_ownership', { target_household: anaHome.id, new_owner: cy.id });
  assert.deepEqual((await owners(ana, anaHome.id)).map(m => m.user_id), [cy.id]);
  const cyLeaving = await rpc(cy, 'preview_household_move');
  assert.equal(cyLeaving.successor.user_id, ana.id, 'The longest-standing member succeeds the owner');
  assert.equal(cyLeaving.deletes_household, false);
  const cySolo = await leave(cy);
  assert.notEqual(cySolo.household.id, anaHome.id);
  assert.deepEqual((await owners(ana, anaHome.id)).map(m => m.user_id), [ana.id], 'Exactly one owner remains');
  assert.equal((await owners(cy, cySolo.household.id))[0].user_id, cy.id, 'Leaving starts a solo household');
  assert.equal((await rows(cy, `recipes?id=eq.${cyPie.id}`)).length, 1, 'Leaving keeps the personal collection');
  assert.equal((await titled(ben, 'Cy pie')).filter(r => r.household_id === anaHome.id).length, 1, 'The household keeps a copy');
  assert.equal((await rows(ben, `recipes?id=eq.${cyPie.id}`)).length, 0, 'The original leaves with its owner');
  console.log('PASS: owners transfer manually or automatically, and departures keep household copies');

  // Leaving with the optional bulk save.
  const householdRecipes = (await rows(ben, `recipes?household_id=eq.${anaHome.id}`)).length;
  const benSoup = await addRecipe(ben, 'Ben soup');
  const benSolo = await leave(ben, true);
  const benOwn = await rows(ben, `recipes?owner_id=eq.${ben.id}`);
  assert.equal(benOwn.filter(r => r.id !== benSoup.id && r.id !== benCopy.id).length, householdRecipes, 'Bulk save copies every household recipe');
  assert(benOwn.filter(r => r.id !== benSoup.id && r.id !== benCopy.id).every(r => !r.is_shared), 'Bulk-saved copies start Only me');
  assert.equal((await rows(ben, `grocery_items?household_id=eq.${benSolo.household.id}`)).length, 0);
  assert.equal((await rows(ben, `planned_meals?household_id=eq.${anaHome.id}`)).length, 0, 'Meals stay with the former household');
  assert.equal((await titled(ana, 'Ben soup')).filter(r => r.household_id === anaHome.id).length, 1);
  console.log('PASS: leaving can save household recipes privately and leaves groceries and meals behind');

  // Removal, with Realtime notice on the removed person's private topic.
  const deeChannel = await listen(dee, `user:${dee.id}`);
  await listen(ana, `user:${dee.id}`, true);
  await join(dee, anaHome.invite_code, deeHome.id);
  await deeChannel.change('household_members');
  const deeShared = await addRecipe(dee, 'Dee curry');
  const oldCode = (await household(ana, anaHome.id)).invite_code;
  await rejects(() => rpc(dee, 'remove_household_member', { target_household: anaHome.id, target_user: ana.id }), ['42501']);
  await rpc(ana, 'remove_household_member', { target_household: anaHome.id, target_user: dee.id });
  await deeChannel.change('household_members');
  const deeNow = await householdOf(dee);
  assert(deeNow && deeNow !== anaHome.id, 'A removed member gets a fresh solo household');
  assert.equal((await rows(dee, `recipes?id=eq.${deeShared.id}`)).length, 1, 'Removal keeps the personal collection');
  assert.equal((await titled(ana, 'Dee curry')).filter(r => r.household_id === anaHome.id).length, 1);
  assert.equal((await rows(dee, `recipes?household_id=eq.${anaHome.id}`)).length, 0, 'Removal revokes household access');
  await listen(dee, `household:${anaHome.id}`, true);
  assert.notEqual((await household(ana, anaHome.id)).invite_code, oldCode, 'Removal rotates the invite code');
  await rejects(() => join(dee, oldCode, deeNow), ['P0002']);
  console.log('PASS: removal provisions a solo household, keeps copies, revokes access, and rotates the code');

  // Simultaneous departures never leave an ownerless or partly deleted household.
  const eve = await person('Eve');
  const fay = await person('Fay');
  const eveHome = await rpc(eve, 'start_household', { member_name: 'Eve' });
  await rpc(fay, 'start_household', { member_name: 'Fay', code: eveHome.invite_code });
  await Promise.all([leave(eve), leave(fay)]);
  for (const p of [eve, fay]) {
    assert.equal((await membership(p)).length, 1);
    assert.notEqual(await householdOf(p), eveHome.id);
    assert.equal((await owners(p, await householdOf(p))).length, 1);
  }
  const orphan = execFileSync('supabase', ['db', 'query', '--linked', `select count(*) as n from public.households where id = '${eveHome.id}'`], { encoding: 'utf8' });
  assert.match(orphan, /"n": 0/, 'Simultaneous departures delete the emptied household');
  console.log('PASS: simultaneous departures resolve to one owner each and no empty household');

  // Deleting household data keeps personal collections.
  const anaKeep = await addRecipe(ana, 'Ana keeps this');
  await rejects(() => rpc(dee, 'delete_household_data', { target_household: anaHome.id }), ['42501']);
  await rpc(ana, 'delete_household_data', { target_household: anaHome.id });
  assert.equal((await rows(ana, `recipes?household_id=eq.${anaHome.id}`)).length, 0);
  assert.equal((await rows(ana, `recipes?id=eq.${anaKeep.id}`)).length, 1, 'Personal recipes survive household data deletion');
  console.log('PASS: deleting household data leaves personal recipes alone');

  {
  // Bulk saves on JOIN must remain private even though the pre-existing collection becomes shared.
  const eve = await person('Eve');
  const eveHome = await rpc(eve, 'start_household', { member_name: 'Eve' });
  const eveOriginal = await addRecipe(eve, 'Eve original');
  await rpc(eve, 'set_recipe_sharing', { target_recipe: eveOriginal.id, shared: false });
  assert.equal((await titled(eve, 'Eve original')).filter(r => r.household_id === eveHome.id).length, 1,
    'Ending sharing retains a household copy even when the household is solo');
  const eveDeleted = await addRecipe(eve, 'Eve deleted');
  await rpc(eve, 'delete_recipe', { target_recipe: eveDeleted.id });
  assert.equal((await titled(eve, 'Eve deleted')).filter(r => r.household_id === eveHome.id).length, 1,
    'Deleting a shared original retains its solo household copy');
  const destination = await household(ana, await householdOf(ana));
  await join(eve, destination.invite_code, eveHome.id, true);
  const eveCollection = await rows(eve, `recipes?owner_id=eq.${eve.id}`);
  assert.equal(eveCollection.find(r => r.id === eveOriginal.id).is_shared, true);
  assert.equal(eveCollection.filter(r => r.id !== eveOriginal.id).length, 2);
  assert(eveCollection.filter(r => r.id !== eveOriginal.id).every(r => !r.is_shared),
    'Bulk-saved household recipes must start Only me when joining');
  console.log('PASS: solo sharing retention and private bulk saves on joining');
  const stays = await person('Stays');
  const staysHome = await rpc(stays, 'start_household', { member_name: 'Stays' });
  for (let index = 0; index < 3; index++) {
    const mover = await person(`Mover ${index}`);
    await rpc(mover, 'start_household', { member_name: mover.name, code: staysHome.invite_code });
    const original = await addRecipe(mover, `Concurrent contribution ${index}`);
    await Promise.all([
      rpc(mover, 'set_recipe_sharing', { target_recipe: original.id, shared: false }),
      join(mover, destination.invite_code, staysHome.id),
    ]);
    assert.equal((await titled(stays, original.title)).filter(r => r.household_id === staysHome.id).length, 1,
      'Concurrent unsharing and a move retain exactly one contribution in the former household');
    assert.equal((await membership(mover)).length, 1);
  }
  console.log('PASS: concurrent sharing-ending actions and moves do not duplicate former-household copies');

  }

} finally {
  for (const ws of sockets) ws.close();
  const failures = [];
  const ids = people.map(p => p.id).filter(id => /^[0-9a-f-]{36}$/.test(id));
  if (ids.length) {
    // service_role intentionally lacks household DELETE; remove exactly the fixtures' households.
    try {
      execFileSync('supabase', ['db', 'query', '--linked', `delete from public.households where id in (
        select household_id from public.household_members where user_id in (${ids.map(id => `'${id}'`).join(',')}));`], { stdio: 'pipe' });
    } catch { failures.push('households'); }
  }
  const results = await Promise.allSettled(people.map(p => request('/auth/v1/logout?scope=global', p.token, 'POST')));
  results.push(...await Promise.allSettled(people.map(p => request(`/auth/v1/admin/users/${p.id}`, admin, 'DELETE', undefined, true))));
  // Copies keep using a photo until their accounts are gone, so photos go last.
  if (photos.length) {
    try { await request('/storage/v1/object/recipe-images', admin, 'DELETE', { prefixes: photos }, true); }
    catch { failures.push('photos'); }
  }
  if (failures.length || results.some(r => r.status === 'rejected')) {
    throw new Error(`Temporary fixture cleanup failed (${failures.join(', ') || 'accounts'}); inspect calendish-moves test users`);
  }
  console.log('Temporary test households and accounts removed');
}
