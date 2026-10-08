// Run with `node scripts/test-profile-photos.mjs` while logged into Supabase CLI.
// Verify avatar persistence and private Storage access with temporary authenticated users.
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
  const email = `calendish-avatar-${randomUUID()}@example.com`;
  const password = randomUUID() + randomUUID();
  const created = await request('/auth/v1/admin/users', admin, 'POST', { email, password, email_confirm: true }, true);
  const session = await request('/auth/v1/token?grant_type=password', publicKey, 'POST', { email, password });
  const p = { id: created.id, name, token: session.access_token };
  people.push(p);
  return p;
}


const rpc = (p, fn, body = {}) => request(`/rest/v1/rpc/${fn}`, p.token, 'POST', body);
const membership = async p => (await request(`/rest/v1/household_members?user_id=eq.${p.id}&select=*`, p.token))[0];
async function upload(p, path) {
  const response = await fetch(`${base}/storage/v1/object/profile-photos/${path}`, {
    method: 'POST', headers: { apikey: publicKey, Authorization: `Bearer ${p.token}`, 'Content-Type': 'image/jpeg', 'cache-control': '0' },
    body: Buffer.from([255,216,255,217]), signal: AbortSignal.timeout(20000),
  });
  return response.ok;
}
async function canRead(p, path) {
  return (await fetch(`${base}/storage/v1/object/authenticated/profile-photos/${path}?check=${randomUUID()}`, {
    headers: { apikey: publicKey, Authorization: `Bearer ${p.token}` }, signal: AbortSignal.timeout(20000),
  })).ok;
}
try {
  const owner = await person('Avatar Owner');
  const partner = await person('Avatar Partner');
  const outsider = await person('Avatar Outsider');
  for (const p of people) await rpc(p, 'start_household', { member_name: p.name });
  const home = await membership(owner);
  const household = (await request(`/rest/v1/households?id=eq.${home.household_id}&select=*`, owner.token))[0];
  await rpc(partner, 'join_household', { code: household.invite_code, save_household_recipes: false,
    expected_household: (await membership(partner)).household_id });
  const path = `${owner.id}/${randomUUID()}.jpg`;
  assert(await upload(owner, path)); photos.push(path);
  assert(await canRead(owner, path));
  assert(await canRead(partner, path));
  assert.equal(await canRead(outsider, path), false);
  assert.equal(await upload(outsider, `${owner.id}/${randomUUID()}.jpg`), false);
  const url = `calendish-avatar:///${path}`;
  await request(`/rest/v1/household_members?user_id=eq.${owner.id}`, owner.token, 'PATCH', { avatar_url: url });
  assert.equal((await membership(owner)).avatar_url, url);
  const denied = await request(`/rest/v1/household_members?user_id=eq.${owner.id}`, partner.token, 'PATCH', { avatar_url: 'calendish-avatar:removed' });
  assert.equal(denied.length, 0);
  assert.equal((await membership(owner)).avatar_url, url);
  await rpc(partner, 'leave_household', { save_household_recipes: false, expected_household: home.household_id });
  assert.equal(await canRead(partner, path), false);
  await request(`/rest/v1/household_members?user_id=eq.${owner.id}`, owner.token, 'PATCH', { avatar_url: 'calendish-avatar:removed' });
  assert.equal((await membership(owner)).avatar_url, 'calendish-avatar:removed', 'Explicit removal is preserved');
  await rpc(owner, 'leave_household', { save_household_recipes: false, expected_household: home.household_id });
  assert.equal((await membership(owner)).avatar_url, 'calendish-avatar:removed', 'Household moves preserve removal');
  await request('/storage/v1/object/profile-photos', owner.token, 'DELETE', { prefixes: [path] });
  assert.equal(await canRead(owner, path), false);
  console.log('PASS: upload, persisted avatar/removal, member-only reads, cross-user write denial, departed-member denial, and cleanup');
} finally {
  const ids = people.map(p => p.id);
  if (photos.length) await request('/storage/v1/object/profile-photos', admin, 'DELETE', { prefixes: photos }, true);
  if (ids.length) execFileSync('supabase', ['db', 'query', '--linked', `delete from public.households where id in (
    select household_id from public.household_members where user_id in (${ids.map(id => `'${id}'`).join(',')}));`], { stdio: 'pipe' });
  for (const p of people) {
    await request('/auth/v1/logout?scope=global', p.token, 'POST');
    await request(`/auth/v1/admin/users/${p.id}`, admin, 'DELETE', undefined, true);
  }
  console.log('Temporary avatar test accounts and households removed');
}
