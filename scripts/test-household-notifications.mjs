// Live access and queue checks using disposable users. No APNs calls or real alerts.
// Run with `node scripts/test-household-notifications.mjs` while signed into Supabase CLI.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const project = readFileSync(new URL('../supabase/.temp/project-ref', import.meta.url), 'utf8').trim();
const keys = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', project, '--reveal', '-o', 'json'], { encoding: 'utf8' }));
const admin = keys.find(k => k.name === 'service_role')?.api_key;
const publicKey = keys.find(k => k.type === 'publishable')?.api_key ?? keys.find(k => k.name === 'anon')?.api_key;
assert(admin && publicKey, 'Missing project API keys');
const base = `https://${project}.supabase.co`, people = [];
async function request(path, token, method = 'GET', body, administrative = false) {
  const response = await fetch(`${base}${path}`, { method,
    headers: { apikey: administrative ? admin : publicKey, ...(token ? { Authorization: `Bearer ${token}` } : {}),
      'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(20000) });
  const text = await response.text();
  if (!response.ok) {
    const error = new Error(`${method} ${path.split('?')[0]} failed (${response.status}): ${text.slice(0, 180)}`);
    error.status = response.status;
    throw error;
  }
  return text ? JSON.parse(text) : undefined;
}
const rpc = (p, fn, body = {}) => request(`/rest/v1/rpc/${fn}`, p.token, 'POST', body);
const adminRPC = (fn, body = {}) => request(`/rest/v1/rpc/${fn}`, admin, 'POST', body, true);
const rows = path => request(`/rest/v1/${path}`, admin, 'GET', undefined, true);
async function person(name) {
  const email = `calendish-push-${randomUUID()}@example.com`, password = randomUUID() + randomUUID();
  const user = await request('/auth/v1/admin/users', admin, 'POST', { email, password, email_confirm: true }, true);
  people.push(user.id);
  const session = await request('/auth/v1/token?grant_type=password', undefined, 'POST', { email, password });
  return { id: user.id, name, token: session.access_token };
}
const newToken = () => randomUUID().replaceAll('-', '') + randomUUID().replaceAll('-', '');
const register = (p, installation, token, enabled = true, environment = 'sandbox') => rpc(p, 'register_push_device', {
  installation, device_token: token, push_environment: environment, recipes_enabled: enabled,
});
async function addRecipe(p, title, shared = true) {
  const [recipe] = await request('/rest/v1/recipes', p.token, 'POST', { id: randomUUID(), owner_id: p.id, is_shared: shared, title,
    summary: '', servings: 4, ingredients: [], steps: ['Cook.'] });
  return recipe;
}
async function deliveries(recipe) {
  const events = await rows(`recipe_push_events?recipe_id=eq.${recipe.id}`);
  return events.length ? await rows(`recipe_push_deliveries?event_id=eq.${events[0].id}`) : [];
}
async function claim(recipe, environments) {
  const expected = await deliveries(recipe);
  const leases = await adminRPC('claim_recipe_pushes', environments ? { push_environments: environments } : {});
  return leases.filter(l => expected.some(d => d.id === l.id));
}
const prepare = lease => adminRPC('prepare_recipe_push', { delivery_id: lease.id, delivery_lease: lease.lease_id });
const finish = (lease, result, extra = {}) => adminRPC('finish_recipe_push', { delivery_id: lease.id, delivery_lease: lease.lease_id, result, ...extra });
const denied = operation => assert.rejects(operation, e => [401, 403, 404].includes(e.status));

try {
  const ana = await person('Ana'), ben = await person('Ben'), cy = await person('Cy');
  const home = await rpc(ana, 'start_household', { member_name: ana.name });
  await rpc(ben, 'start_household', { member_name: ben.name, code: home.invite_code });
  await rpc(cy, 'start_household', { member_name: cy.name });
  const anaInstall = randomUUID(), benInstall = randomUUID(), benSecond = randomUUID(), cyInstall = randomUUID();
  const anaToken = newToken(), benToken = newToken();
  await register(ana, anaInstall, anaToken);
  await register(ben, benInstall, benToken);
  await register(ben, benSecond, newToken(), true, 'production');
  await register(cy, cyInstall, newToken());
  await register(ben, benInstall, benToken);
  assert.equal((await rows(`push_devices?user_id=eq.${ben.id}`)).length, 2, 'Registration is idempotent and supports multiple devices');
  for (const table of ['push_devices', 'recipe_push_events', 'recipe_push_deliveries']) {
    await denied(() => request(`/rest/v1/${table}?select=*`, ben.token));
  }
  await denied(() => rpc(ben, 'claim_recipe_pushes'));
  await denied(() => rpc(ben, 'prepare_recipe_push', { delivery_id: randomUUID(), delivery_lease: randomUUID() }));
  await denied(() => request('/rest/v1/rpc/register_push_device', undefined, 'POST', {
    installation: randomUUID(), device_token: newToken(), push_environment: 'sandbox', recipes_enabled: true }));
  await assert.rejects(() => register(ana, randomUUID(), 'bad-token'), /400/);
  console.log('PASS: private device registration, multiple devices, and worker authorization');

  const soup = await addRecipe(ana, 'Soup');
  const queued = await deliveries(soup);
  assert.equal(queued.length, 2);
  assert(queued.every(d => d.recipient_id === ben.id), 'Exclude the author and other households');
  const privateRecipe = await addRecipe(ana, 'Private soup', false);
  assert.equal((await deliveries(privateRecipe)).length, 0);
  await request(`/rest/v1/recipes?id=eq.${soup.id}`, ana.token, 'PATCH', { title: 'Tomato soup' });
  assert.equal((await deliveries(soup)).length, 2, 'Edits never enqueue another alert');
  await rpc(ana, 'set_recipe_sharing', { target_recipe: privateRecipe.id, shared: true });
  assert.equal((await deliveries(privateRecipe)).length, 0, 'Sharing older recipes does not create new-recipe alerts');
  const sandbox = await claim(soup, ['sandbox']);
  assert.equal(sandbox.length, 1, 'Unconfigured production deliveries are not claimed by a sandbox worker');
  const production = await claim(soup, ['production']);
  assert.equal(production.length, 1);
  const leases = [...sandbox, ...production];
  assert.equal(leases.length, 2);
  assert.equal((await claim(soup)).length, 0, 'Leased deliveries cannot be claimed again');
  const [payload] = await prepare(leases[0]);
  assert.equal(payload.recipient_id, ben.id);
  assert.equal(payload.title, 'Tomato soup');
  assert.equal(payload.actor_name, 'Ana');
  await finish({ ...leases[0], lease_id: randomUUID() }, 'delivered');
  assert.equal((await prepare(leases[0])).length, 1, 'Wrong lease cannot acknowledge a delivery');
  await finish(leases[0], 'delivered');
  assert.equal((await prepare(leases[0])).length, 0);
  await finish(leases[1], 'retry', { error_reason: 'ServiceUnavailable' });
  const retry = (await deliveries(soup)).find(d => d.id === leases[1].id);
  assert.equal(retry.status, 'pending');
  assert(new Date(retry.available_at) > new Date());
  console.log('PASS: shared additions only, recipient isolation, leases, and delayed retries');

  const withdrawn = await addRecipe(ana, 'Withdrawn recipe');
  const withdrawnLeases = await claim(withdrawn);
  await rpc(ana, 'set_recipe_sharing', { target_recipe: withdrawn.id, shared: false });
  for (const lease of withdrawnLeases) {
    assert.equal((await prepare(lease)).length, 0, 'Visibility is checked immediately before sending');
    await finish(lease, 'cancelled');
  }
  const disabled = await addRecipe(ana, 'Opt-out recipe');
  await register(ben, benInstall, benToken, false);
  assert.equal((await deliveries(disabled)).filter(d => d.status === 'cancelled').length, 1);
  await rpc(ben, 'unregister_push_device', { installation: benSecond });
  assert.equal((await deliveries(disabled)).length, 1, 'Sign-out removes that device and its pending deliveries');
  const noDevices = await addRecipe(ana, 'No alerts');
  assert.equal((await deliveries(noDevices)).length, 0);
  console.log('PASS: private recipes, opt-outs, and sign-out cancel pending alerts');

  await register(ben, benInstall, benToken);
  const moved = await addRecipe(ana, 'Old household');
  const moveLeases = await claim(moved);
  const benHome = await request('/rest/v1/household_members?select=household_id', ben.token);
  await rpc(ben, 'leave_household', { expected_household: benHome[0].household_id, save_household_recipes: false });
  for (const lease of moveLeases) {
    assert.equal((await prepare(lease)).length, 0, 'A former member cannot receive queued household alerts');
    await finish(lease, 'cancelled');
  }
  // Signing in as another account on the same installation cancels deliveries to the old account.
  await register(cy, benInstall, benToken);
  assert.equal((await rows(`push_devices?installation_id=eq.${benInstall}`))[0].user_id, cy.id);
  console.log('PASS: membership changes and account replacement invalidate old deliveries');

  await rpc(ben, 'join_household', { code: home.invite_code, expected_household: (await request('/rest/v1/household_members?select=household_id', ben.token))[0].household_id, save_household_recipes: false });
  const invalidInstall = randomUUID();
  await register(ben, invalidInstall, newToken());
  const invalid = await addRecipe(ana, 'Invalid token');
  const invalidLeases = await claim(invalid);
  for (const lease of invalidLeases) await finish(lease, 'invalid_token', { error_reason: 'Unregistered' });
  assert.equal((await rows(`push_devices?installation_id=eq.${invalidInstall}`)).length, 0);
  // A revoked Auth session cannot re-register using an access token that has not expired yet.
  await request('/auth/v1/logout?scope=global', ben.token, 'POST');
  assert.equal((await rows(`push_devices?user_id=eq.${ben.id}`)).length, 0);
  await denied(() => register(ben, randomUUID(), newToken()));
  console.log('PASS: invalid tokens and revoked sessions cannot keep receiving alerts');
} catch (error) {
  console.error('TEST FAILURE:', error.message);
  process.exitCode = 1;
} finally {
  // Existing deferred membership checks run under the caller's role. Remove fixture households
  // through the linked SQL connection before Auth removes the temporary accounts.
  const ids = people.filter(id => /^[0-9a-f-]{36}$/.test(id));
  if (ids.length) execFileSync('supabase', ['db', 'query', '--linked',
    `delete from public.households where id in (select household_id from public.household_members where user_id in (${ids.map(id => `'${id}'`).join(',')}));`], { stdio: 'pipe' });
  for (const id of people.reverse()) {
    try { await request(`/auth/v1/admin/users/${id}`, admin, 'DELETE', undefined, true); }
    catch (error) { console.error('Fixture cleanup failed for', id, error.message); process.exitCode = 1; }
  }
}
