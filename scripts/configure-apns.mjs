// Upload an Apple signing key without putting private key material in arguments, output, or Git.
// Usage: node scripts/configure-apns.mjs /path/to/AuthKey_KEYID.p8 KEYID TEAMID [sandbox|production|both]
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { importAPNsKey } from '../supabase/functions/household-recipe-push/delivery.ts';

const [path, keyID, teamID, environment = 'sandbox'] = process.argv.slice(2);
if (!['sandbox', 'production', 'both'].includes(environment) || !path || !/^[A-Z0-9]{10}$/.test(keyID ?? '') || !/^[A-Z0-9]{10}$/.test(teamID ?? '')) {
  console.error('Usage: node scripts/configure-apns.mjs /path/to/key.p8 KEYID TEAMID [sandbox|production|both]');
  process.exit(1);
}
const pem = readFileSync(path, 'utf8');
await importAPNsKey(pem);
const directory = mkdtempSync(join(tmpdir(), 'calendish-apns-'));
try {
  const file = join(directory, '.env');
  const prefix = environment === 'both' ? 'APNS_' : `APNS_${environment.toUpperCase()}_`;
  writeFileSync(file, `${prefix}PRIVATE_KEY="${pem.trim().replaceAll('\n', '\\n')}"\n${prefix}KEY_ID=${keyID}\nAPNS_TEAM_ID=${teamID}\n`, { mode: 0o600 });
  execFileSync('supabase', ['secrets', 'set', '--env-file', file], { stdio: 'pipe' });
  execFileSync('supabase', ['functions', 'deploy', 'household-recipe-push', '--use-api'], { stdio: 'pipe' });
  console.log('APNs credentials uploaded and household recipe delivery redeployed. Enable household recipes on each iPhone, then test a new shared recipe.');
} catch {
  console.error('Couldn’t configure APNs. Check that Supabase CLI is signed in and linked to the Calendish project, then try again.');
  process.exitCode = 1;
} finally {
  rmSync(directory, { recursive: true, force: true });
}
