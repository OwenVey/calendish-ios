export type PushKind = 'recipe' | 'groceries' | 'member_joined' | 'member_removed';

export interface PushContent {
  token: string;
  environment: 'sandbox' | 'production';
  recipient_id: string;
  household_id: string;
  kind: PushKind;
  actor_name: string | null;
  recipe_id: string | null;
  recipe_title: string | null;
  household_name: string | null;
  item_count: number | null;
  item_names: string[] | null;
  expires_at: string;
}

export interface Lease { id: string; lease_id: string }
export type PushResult = 'delivered' | 'retry' | 'failed' | 'cancelled' | 'invalid_token';
export interface Worker {
  claim(): Promise<Lease[]>;
  prepare(lease: Lease): Promise<PushContent | undefined>;
  send(lease: Lease, content: PushContent): Promise<{ result: PushResult; reason?: string }>;
  finish(lease: Lease, result: PushResult, reason?: string): Promise<void>;
}

// This module has no runtime dependencies and is tested with Node's built-in test runner.
const clip = (value: string | null, length: number) => (value ?? '').trim().slice(0, length);
const list = new Intl.ListFormat('en', { type: 'conjunction' });

function alert(content: PushContent): { title: string; body: string; thread: string } {
  const actor = clip(content.actor_name, 100) || 'Someone in your household';
  const thread = `household:${content.household_id}`;
  switch (content.kind) {
    case 'recipe':
      return { title: `${actor} added a recipe`, body: clip(content.recipe_title, 200), thread };
    case 'groceries': {
      const count = Math.max(content.item_count ?? 0, 1);
      const names = (content.item_names ?? []).map(name => clip(name, 60)).filter(Boolean).slice(0, 3);
      const more = count - names.length;
      return {
        title: count === 1 ? `${actor} added an item to groceries` : `${actor} added ${count} items to groceries`,
        body: names.length ? list.format(more > 0 ? [...names, `${more} more`] : names) : 'Open your grocery list to see what’s new.',
        thread: `${thread}:groceries`,
      };
    }
    case 'member_joined':
      return { title: `${actor} joined your household`, body: 'They can now see shared recipes, the meal plan, and groceries.', thread: `${thread}:members` };
    case 'member_removed': {
      const home = clip(content.household_name, 100);
      return {
        title: home ? `You were removed from ${home}` : 'You were removed from a household',
        body: 'Its recipes, meal plan, and groceries are no longer shared with you. Your own recipes are still here.',
        thread: `${thread}:members`,
      };
    }
  }
}

const types: Record<PushKind, string> = {
  recipe: 'household_recipe', groceries: 'household_groceries', member_joined: 'household_member_joined', member_removed: 'household_member_removed',
};

export function notificationPayload(content: PushContent) {
  const { title, body, thread } = alert(content);
  return {
    aps: { alert: { title, body }, sound: 'default', 'thread-id': thread },
    type: types[content.kind], household_id: content.household_id, recipient_id: content.recipient_id,
    ...(content.kind === 'recipe' ? { recipe_id: content.recipe_id } : {}),
  };
}

export function apnsResult(status: number, reason?: string): PushResult {
  if (status === 200) return 'delivered';
  if (status === 410 || (status === 400 && ['BadDeviceToken', 'DeviceTokenNotForTopic'].includes(reason ?? ''))) return 'invalid_token';
  if (status === 429 || status >= 500 || status === 403) return 'retry';
  return 'failed';
}

export async function deliverBatch(worker: Worker) {
  const leases = await worker.claim();
  const counts = { delivered: 0, retry: 0, failed: 0, cancelled: 0, invalid_token: 0 };
  // Bound simultaneous APNs requests and leave enough time to acknowledge the leases.
  for (let start = 0; start < leases.length; start += 5) {
    await Promise.all(leases.slice(start, start + 5).map(async lease => {
      let result: PushResult = 'retry';
      let reason: string | undefined;
      try {
        const content = await worker.prepare(lease);
        if (!content) result = 'cancelled';
        else ({ result, reason } = await worker.send(lease, content));
      } catch {
        reason = 'TransportError';
      }
      // A failed acknowledgement leaves the lease for retry; do not report it as completed.
      await worker.finish(lease, result, reason);
      counts[result]++;
    }));
  }
  return counts;
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export async function importAPNsKey(pem: string): Promise<CryptoKey> {
  const data = pem.replaceAll('\\n', '\n').replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  return await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(data), c => c.charCodeAt(0)),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
}

export async function apnsJWT(key: CryptoKey, keyID: string, teamID: string, issuedAt = Math.floor(Date.now() / 1000)) {
  const encode = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${encode({ alg: 'ES256', kid: keyID })}.${encode({ iss: teamID, iat: issuedAt })}`;
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(new Uint8Array(signature))}`;
}
