import { apnsJWT, apnsResult, deliverBatch, importAPNsKey, notificationPayload } from './delivery.ts';
import type { Lease, PushContent, PushResult } from './delivery.ts';

const topic = 'owenvey.calendish';
const providerTokens = new Map<string, { value: string; created: number; pem: string; keyID: string; teamID: string }>();

async function authorized(provided: string, expected: string) {
  const digest = (value: string) => crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  const [left, right] = await Promise.all([digest(provided), digest(expected)]);
  const a = new Uint8Array(left), b = new Uint8Array(right);
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a[index] ^ b[index];
  return difference === 0;
}

Deno.serve(async request => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const workerSecret = Deno.env.get('RECIPE_PUSH_WORKER_SECRET');
  if (!workerSecret || !await authorized(request.headers.get('x-push-worker-secret') ?? '', workerSecret)) {
    return new Response('Unauthorized', { status: 401 });
  }
  const credentials = ['sandbox', 'production'].flatMap(environment => {
    const prefix = `APNS_${environment.toUpperCase()}_`;
    const pem = Deno.env.get(`${prefix}PRIVATE_KEY`) ?? Deno.env.get('APNS_PRIVATE_KEY');
    const keyID = Deno.env.get(`${prefix}KEY_ID`) ?? Deno.env.get('APNS_KEY_ID');
    const teamID = Deno.env.get('APNS_TEAM_ID');
    return pem && keyID && teamID ? [{ environment, pem, keyID, teamID }] : [];
  });
  const base = Deno.env.get('SUPABASE_URL');
  const admin = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    ?? JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}').default;
  if (!credentials.length || !base || !admin) {
    return Response.json({ error: 'Push delivery is not configured' }, { status: 503 });
  }
  async function rpc<T>(name: string, params: Record<string, unknown> = {}): Promise<T> {
    const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { apikey: admin!, Authorization: `Bearer ${admin}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(params), signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error(`Push RPC failed (${response.status})`);
    const body = await response.text();
    return (body ? JSON.parse(body) : undefined) as T;
  }
  try {
    // Validate signing credentials before claiming anything, so setup errors do not consume retries.
    const now = Math.floor(Date.now() / 1000);
    for (const credential of credentials) {
      const { environment, pem, keyID, teamID } = credential;
      const cached = providerTokens.get(environment);
      if (!cached || now - cached.created >= 50 * 60 || cached.pem !== pem || cached.keyID !== keyID || cached.teamID !== teamID) {
        const key = await importAPNsKey(pem);
        providerTokens.set(environment, { value: await apnsJWT(key, keyID, teamID, now), created: now, pem, keyID, teamID });
      }
    }
    const result = await deliverBatch({
      claim: () => rpc<Lease[]>('claim_household_pushes', { batch_size: 25, push_environments: credentials.map(c => c.environment) }),
      prepare: async lease => (await rpc<PushContent[]>('prepare_household_push', {
        delivery_id: lease.id, delivery_lease: lease.lease_id,
      }))[0],
      send: async (lease, content) => {
        const host = content.environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
        // Deno negotiates HTTP/2 over TLS, as required by APNs.
        const response = await fetch(`https://${host}/3/device/${content.token}`, {
          method: 'POST', headers: {
            authorization: `bearer ${providerTokens.get(content.environment)!.value}`, 'apns-topic': topic, 'apns-push-type': 'alert', 'apns-priority': '10',
            'apns-id': lease.id, 'apns-collapse-id': lease.id,
            'apns-expiration': String(Math.floor(new Date(content.expires_at).getTime() / 1000)),
          }, body: JSON.stringify(notificationPayload(content)), signal: AbortSignal.timeout(8000),
        });
        const error = response.ok ? undefined : await response.json().catch(() => ({}));
        const reason = typeof error?.reason === 'string' ? error.reason : undefined;
        if (reason === 'ExpiredProviderToken') providerTokens.delete(content.environment);
        return { result: apnsResult(response.status, reason), reason };
      },
      finish: (lease: Lease, result: PushResult, reason?: string) => rpc<void>('finish_household_push', {
        delivery_id: lease.id, delivery_lease: lease.lease_id, result, error_reason: reason ?? null,
      }),
    });
    return Response.json(result);
  } catch {
    // Never log APNs tokens, credentials, or household contents.
    console.error('Household push worker failed; pending leases will retry.');
    return Response.json({ error: 'Push delivery temporarily unavailable' }, { status: 503 });
  }
});
