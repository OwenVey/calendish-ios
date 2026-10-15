export interface PushContent {
  token: string;
  environment: 'sandbox' | 'production';
  recipient_id: string;
  recipe_id: string;
  household_id: string;
  title: string;
  actor_name: string;
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
export function notificationPayload(content: PushContent) {
  const actor = content.actor_name.trim().slice(0, 100) || 'Someone in your household';
  return {
    aps: {
      alert: { title: `${actor} added a recipe`, body: content.title.slice(0, 200) },
      sound: 'default', 'thread-id': `household:${content.household_id}`,
    },
    type: 'household_recipe', recipe_id: content.recipe_id,
    household_id: content.household_id, recipient_id: content.recipient_id,
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
