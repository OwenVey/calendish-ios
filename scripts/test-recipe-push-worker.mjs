// Pure worker tests: no credentials, network, or live notifications.
import test from 'node:test';
import assert from 'node:assert/strict';
import { apnsJWT, apnsResult, deliverBatch, importAPNsKey, notificationPayload } from '../supabase/functions/household-recipe-push/delivery.ts';

const content = { token: 'a'.repeat(64), environment: 'sandbox', recipient_id: 'recipient', recipe_id: 'recipe',
  household_id: 'home', title: 'Lemon & herb orzo', actor_name: 'Owen', expires_at: new Date(Date.now() + 3600000).toISOString() };

test('payload opens the recipe only for the intended account and household', () => {
  const payload = notificationPayload(content);
  assert.equal(payload.aps.alert.title, 'Owen added a recipe');
  assert.equal(payload.aps.alert.body, content.title);
  assert.equal(payload.type, 'household_recipe');
  assert.equal(payload.recipient_id, content.recipient_id);
  assert.equal(payload.household_id, content.household_id);
  assert.equal(payload.recipe_id, content.recipe_id);
  assert.equal(payload.aps['thread-id'], 'household:home');
  assert(!JSON.stringify(payload).includes(content.token));
  const long = notificationPayload({ ...content, title: '🍋'.repeat(2000), actor_name: '🥘'.repeat(2000) });
  assert(Buffer.byteLength(JSON.stringify(long)) < 4096);
  assert.match(notificationPayload({ ...content, actor_name: ' ' }).aps.alert.title, /^Someone in your household/);
});

test('APNs invalid tokens are removed, transient errors retry, permanent errors stop', () => {
  assert.equal(apnsResult(200), 'delivered');
  assert.equal(apnsResult(410, 'Unregistered'), 'invalid_token');
  assert.equal(apnsResult(400, 'BadDeviceToken'), 'invalid_token');
  assert.equal(apnsResult(400, 'DeviceTokenNotForTopic'), 'invalid_token');
  for (const code of [403, 429, 500, 503]) assert.equal(apnsResult(code), 'retry');
  assert.equal(apnsResult(400, 'BadPayload'), 'failed');
  assert.equal(apnsResult(413), 'failed');
});

test('worker checks current visibility, skips cancelled deliveries, and records retries', async () => {
  const finished = [], sent = [];
  const result = await deliverBatch({
    claim: async () => [{ id: 'ok' }, { id: 'removed' }, { id: 'offline' }, { id: 'invalid' }],
    prepare: async lease => lease.id === 'removed' ? undefined : content,
    send: async lease => {
      sent.push(lease.id);
      if (lease.id === 'offline') throw new Error('network unavailable');
      return { result: lease.id === 'invalid' ? 'invalid_token' : 'delivered' };
    },
    finish: async (lease, result, reason) => finished.push({ id: lease.id, result, reason }),
  });
  assert.deepEqual(sent.sort(), ['invalid', 'offline', 'ok']);
  assert.deepEqual(result, { delivered: 1, retry: 1, failed: 0, cancelled: 1, invalid_token: 1 });
  assert.equal(finished.find(x => x.id === 'offline').reason, 'TransportError');
});

test('unacknowledged delivery throws so its database lease can retry', async () => {
  await assert.rejects(() => deliverBatch({ claim: async () => [{ id: 'one' }], prepare: async () => content,
    send: async () => ({ result: 'delivered' }), finish: async () => { throw new Error('lost response'); } }), /lost response/);
});

test('APNs provider token is a valid ES256 signature with the required claims', async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64')}\n-----END PRIVATE KEY-----`;
  const key = await importAPNsKey(pem);
  const jwt = await apnsJWT(key, 'KEY1234567', 'Q97ES87SKW', 1000);
  const [header, claims, signature] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: 'KEY1234567' });
  assert.deepEqual(JSON.parse(Buffer.from(claims, 'base64url')), { iss: 'Q97ES87SKW', iat: 1000 });
  assert.equal(Buffer.from(signature, 'base64url').length, 64);
  assert(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pair.publicKey,
    Buffer.from(signature, 'base64url'), Buffer.from(`${header}.${claims}`)));
});
