// Run with `node scripts/test-auto-plan-saves.mjs` while logged into Supabase CLI.
// Exercises guarded auto-plan saves as signed-in members: recipe revisions, occupied days, reviewed
// versions, membership, idempotent retries, and concurrent writes. Administrative credentials only
// create and remove the temporary accounts and their households.
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
  const email = `calendish-autoplan-${randomUUID()}@example.com`;
  const password = randomUUID() + randomUUID();
  const created = await request('/auth/v1/admin/users', admin, 'POST', { email, password, email_confirm: true }, true);
  const session = await request('/auth/v1/token?grant_type=password', publicKey, 'POST', { email, password });
  const p = { id: created.id, name, token: session.access_token };
  people.push(p);
  return p;
}

const rpc = (p, fn, body = {}) => request(`/rest/v1/rpc/${fn}`, p.token, 'POST', body);
const rows = (p, path) => request(`/rest/v1/${path}`, p.token);
const recipe = async (p, id) => (await rows(p, `recipes?id=eq.${id}&select=*`))[0];
const mealsOn = (p, home, day) => rows(p, `planned_meals?household_id=eq.${home}&date=eq.${day}&select=*`);
async function rejects(operation, codes) {
  await assert.rejects(operation, error => {
    if (codes && !codes.includes(error.code) && !codes.includes(error.status)) throw error;
    return true;
  });
}
async function addRecipe(p, title, shared = true) {
  const [row] = await request('/rest/v1/recipes', p.token, 'POST', {
    id: randomUUID(), owner_id: p.id, is_shared: shared, title, summary: '', servings: 4, category: 'Dinner',
    ingredients: [{ id: randomUUID(), text: '1 cup rice' }], steps: ['Cook.'],
  });
  return row;
}
const edit = (p, id, changes) => request(`/rest/v1/recipes?id=eq.${id}`, p.token, 'PATCH', changes);
const add = (p, home, day, r, revision, id = randomUUID(), servings = 3) =>
  rpc(p, 'add_planned_meal', { target_household: home, meal_id: id, meal_date: day, meal_recipe: r.id, expected_revision: revision, meal_servings: servings });
let dayCounter = 0;
// Far-future days that no other fixture uses.
const nextDay = () => `2098-0${1 + Math.floor(dayCounter / 28)}-${String(1 + (dayCounter++ % 28)).padStart(2, '0')}`;

try {
  const ana = await person('Ana');
  const ben = await person('Ben');
  const cy = await person('Cy');
  const home = (await rpc(ana, 'start_household', { member_name: 'Ana' })).id;
  await rpc(ben, 'start_household', { member_name: 'Ben', code: (await rows(ana, `households?id=eq.${home}&select=*`))[0].invite_code });
  const cyHome = (await rpc(cy, 'start_household', { member_name: 'Cy' })).id;

  // Revisions ---------------------------------------------------------------
  const soup = await addRecipe(ana, 'Soup');
  assert.equal(soup.revision, 1, 'New recipes start at revision 1');
  await edit(ana, soup.id, { title: 'Tomato soup' });
  assert.equal((await recipe(ana, soup.id)).revision, 2, 'Content edits advance the revision');
  await edit(ana, soup.id, { title: 'Tomato soup' });
  assert.equal((await recipe(ana, soup.id)).revision, 2, 'Saving unchanged content keeps the revision');
  await rejects(() => edit(ana, soup.id, { revision: 99 }), ['42501']);
  await rpc(ana, 'set_recipe_sharing', { target_recipe: soup.id, shared: true });
  assert.equal((await recipe(ana, soup.id)).revision, 2, 'Sharing changes keep the revision');
  console.log('PASS: recipes count content edits only');

  // Guarded adds ------------------------------------------------------------
  const day = nextDay();
  assert.equal(await add(ana, home, day, soup, 2, undefined, 5), 'added');
  const [saved] = await mealsOn(ben, home, day);
  assert.equal(saved.recipe.title, 'Tomato soup');
  assert.equal(saved.servings, 5);
  assert.equal(saved.recipe_id, soup.id);
  assert.equal(await add(ana, home, day, soup, 2, saved.id), 'already_added', 'A retried meal is recognized before occupancy');
  assert.equal((await mealsOn(ana, home, day)).length, 1, 'A retry adds nothing');
  console.log('PASS: guarded adds capture the reviewed version and retries are idempotent');

  const mealDay = nextDay();
  await rpc(ben, 'save_planned_meal', { target_household: home, meal_id: randomUUID(), meal_date: mealDay, meal_recipe: soup.id, meal_servings: 2 });
  assert.equal(await add(ana, home, mealDay, soup, 2), 'occupied', 'A day with a recipe is occupied');
  const noteDay = nextDay();
  await request('/rest/v1/meal_plan_notes', ben.token, 'POST', { id: randomUUID(), household_id: home, date: noteDay, text: 'Dinner out' });
  assert.equal(await add(ana, home, noteDay, soup, 2), 'occupied', 'A day with a note is occupied');
  assert.equal((await mealsOn(ana, home, mealDay)).length + (await mealsOn(ana, home, noteDay)).length, 1, 'Occupied days are left alone');
  const secondManual = await rpc(ben, 'save_planned_meal', { target_household: home, meal_id: randomUUID(), meal_date: mealDay, meal_recipe: soup.id, meal_servings: 2 });
  assert.equal(secondManual.date, mealDay, 'Manual planning still allows several recipes a day');
  console.log('PASS: occupied days are skipped and manual planning is unchanged');

  const staleDay = nextDay();
  assert.equal(await add(ana, home, staleDay, soup, 1), 'changed', 'A stale revision is rejected');
  const secret = await addRecipe(cy, 'Private', false);
  assert.equal(await add(ana, home, staleDay, secret, 1), 'unavailable', 'Another household\'s recipe is unavailable');
  const gone = await addRecipe(ana, 'Gone');
  await rpc(ana, 'delete_recipe', { target_recipe: gone.id });
  assert.equal(await add(ana, home, staleDay, gone, 1), 'unavailable', 'A deleted recipe is unavailable');
  assert.equal((await mealsOn(ana, home, staleDay)).length, 0, 'Rejected adds write nothing');
  await rejects(() => add(cy, home, staleDay, soup, 2), ['42501']);
  await rejects(() => add(ana, cyHome, staleDay, soup, 2), ['42501']);
  await rejects(() => add(cy, cyHome, staleDay, soup, 2, saved.id), ['42501']);
  console.log('PASS: stale, unavailable, and non-member adds are rejected');

  // Concurrency -------------------------------------------------------------
  for (let i = 0; i < 4; i++) {
    const race = nextDay();
    const results = await Promise.all([add(ana, home, race, soup, 2), add(ben, home, race, soup, 2)]);
    assert.deepEqual(results.sort(), ['added', 'occupied'], 'Concurrent adds fill a day only once');
    const id = randomUUID();
    const retry = nextDay();
    assert.deepEqual((await Promise.all([add(ana, home, retry, soup, 2, id), add(ana, home, retry, soup, 2, id)])).sort(),
      ['added', 'already_added'], 'Concurrent retries add one meal');
    const noted = nextDay();
    const [added] = await Promise.all([add(ana, home, noted, soup, 2),
      request('/rest/v1/meal_plan_notes', ben.token, 'POST', { id: randomUUID(), household_id: home, date: noted, text: 'Leftovers' })]);
    assert.ok(['added', 'occupied'].includes(added), 'A concurrent note either lands first or after the add');
  }
  for (let i = 0; i < 4; i++) {
    const current = await recipe(ana, soup.id);
    const editDay = nextDay();
    const title = `Soup ${i}`;
    const [result] = await Promise.all([add(ben, home, editDay, current, current.revision), edit(ana, soup.id, { title })]);
    const meals = await mealsOn(ana, home, editDay);
    if (result === 'added') {
      assert.equal(meals[0].recipe.title, current.title, 'An add racing an edit captures the reviewed version');
    } else {
      assert.equal(result, 'changed');
      assert.equal(meals.length, 0, 'A rejected add writes nothing');
    }
  }
  console.log('PASS: concurrent adds, retries, notes, and edits keep the guarantees');

  const leaveDay = nextDay();
  await rpc(ben, 'leave_household', { save_household_recipes: false, expected_household: home });
  const revision = (await recipe(ana, soup.id)).revision;
  await rejects(() => add(ben, home, leaveDay, soup, revision), ['42501']);
  assert.equal((await mealsOn(ana, home, leaveDay)).length, 0);
  console.log('PASS: a former member cannot add dinners');
} finally {
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
  if (failures.length || results.some(r => r.status === 'rejected')) {
    throw new Error(`Temporary fixture cleanup failed (${failures.join(', ') || 'accounts'}); inspect calendish-autoplan test users`);
  }
  console.log('Temporary test households and accounts removed');
}
