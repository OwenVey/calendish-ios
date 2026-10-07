# Supabase review — October 7, 2026

Reviewed the native Swift client, Auth, household data access, Realtime, private
recipe Storage, migration history, and hosted security/performance advisors using
both project Supabase skills and the current Supabase documentation/changelog.

## Changes applied

- **Realtime:** one private `household:<uuid>` Broadcast channel per household.
  Database triggers broadcast only a table name; the app refetches authorized data
  through RLS. Members have receive permission, with no client publish permission.
  Recipes, groceries, meals, household names, and member profiles all notify the
  channel. Subscription/reconnection triggers a catch-up fetch. The existing
  Postgres Changes publication remains enabled for older installed versions.
- **Privileged functions:** moved the membership helper and household creation/join
  implementations into the unexposed `private` schema. Public creation/join RPCs
  are invoker wrappers. Internal implementations retain explicit identity checks,
  empty search paths, and narrowly granted execution. The platform's automatic RLS
  event-trigger function no longer has client execution grants. Future functions
  default to no anonymous/authenticated execution until explicitly granted.
- **Meal integrity:** a composite foreign key requires a meal's recipe to belong
  to its household. `save_planned_meal` is an invoker RPC that atomically moves or
  replaces a meal; errors roll back the removal. Concurrent slot saves use the
  existing unique constraint and `ON CONFLICT`.
- **Grocery writes:** atomic invoker RPC for reordering updates positions only,
  preserving checkmarks and avoiding resurrection of deleted rows. Explicit
  household authorization and parameter validation protect the RPC.
- **Recipe observation:** recipe equality includes stored content, so a refetched
  recipe with the same ID but changed servings, times, or other fields notifies
  SwiftUI. Broadcast routing reads the SDK envelope's nested `payload.table`.
- **Client concurrency:** queued writes retain local edits during refetches.
  Account changes invalidate reads and cancel queued/in-flight saves before
  clearing account data. Favorite changes update only the favorite field.
  Grocery revisions and pending field overlays protect overlapping shopper edits.
- **Pagination:** keyset pagination by UUID loads household collections in batches
  of 500, avoiding the default Data API row limit. Recipes keep creation-date
  ordering; groceries keep position ordering after merging pending changes.
- **Password policy:** raised the minimum for new/reset passwords from six to
  eight characters in the UI, local config, and hosted Auth. A minimal declared
  config change was previewed and verified after pushing; Google provider and
  callback settings were preserved. Existing six-character passwords remain
  accepted by the sign-in form.
- **Private photo cache:** clear memory/disk caches on account changes and cancel
  pending downloads; generation checks prevent old downloads repopulating caches.

Applied migration:
`supabase/migrations/20261007171436_harden_household_access_and_realtime.sql`.

## Existing practices verified

- The app embeds only a publishable key; no administrative key is shipped.
- All five exposed application tables have RLS with household-based authorization.
  User-editable metadata is used only for presentation, not permissions.
- Swift SDK session persistence uses Keychain by default, automatically refreshes
  tokens around iOS lifecycle changes, and updates Realtime authentication.
- Google native sign-in supplies the hashed nonce to Google and the original nonce
  to Supabase. Hosted Google/email sign-in is enabled, anonymous sign-in is
  disabled, and an admin-generated recovery link verified the custom app callback
  without sending email.
- Recipe images are in a private bucket, restricted to household folders and JPEGs
  up to 10 MiB. Uploads use fresh paths without Storage upsert, so an UPDATE policy
  is intentionally unnecessary.
- SDK versions/revisions are recorded in the committed SwiftPM lockfile.
- Existing RLS lookup and foreign-key indexes are present. The new composite meal
  index supports the new foreign key; its initial unused-index advisory is expected
  before production traffic exercises it.
- Hosted Postgres is 17.11; the reviewed minor-release notices about ltree,
  btree_gist, custom operators, and legacy encrypted pgcrypto data do not apply to
  the application's current schema.

## Verification

- Migration DDL validated in a hosted transaction followed by rollback, then
  deployed through `supabase db push --linked --skip-vault`. Docker is unavailable
  on this machine, so a full local database reset was not run.
- Hosted inspection confirms five RLS-protected app tables, five Broadcast
  triggers, the composite meal foreign key, a private image bucket, and zero
  exposed security-definer functions executable by anonymous/authenticated users.
- `./scripts/test-grocery-sync.sh`: local merge/race regression checks pass.
- `./scripts/test-recipe-observation.sh`: same-ID servings, prep/cook time, title,
  favorite, photo, and ingredient edits notify an observed recipe list; unchanged
  refetches do not.
- `node scripts/test-grocery-realtime.mjs`: disposable accounts in two households
  verify private-channel authorization, internal RPC isolation, RLS reads/writes,
  live additions/checkmarks/deletions, recipe servings/time edits, reconnect
  recovery, atomic meal rollback and
  concurrent slot saves, authorized grocery ordering, >1,000-row pagination, and
  private Storage upload/download isolation. Sessions are revoked and fixtures
  are removed afterward.
- Simulator and physical-device builds are performed using the project scripts.
  Backend tests use separate authenticated connections; they are not a two-phone
  UI test. The Device panel's support installer is currently failing.

## Remaining hosted setting

The security advisor reports **leaked-password protection disabled**. Supabase
requires Pro or above for this feature. No plan upgrade or billing change was made;
this setting should be enabled in Auth's password settings when available.
Local `supabase/config.toml` does not automatically configure hosted Auth settings.
Review hosted configuration before using `supabase config push`, especially Google
provider settings and redirect allowlists.

## Sources

- [Supabase changelog](https://supabase.com/changelog)
- [Recommended database-change subscriptions](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes)
- [Broadcast from the database](https://supabase.com/docs/guides/realtime/broadcast)
- [Realtime authorization](https://supabase.com/docs/guides/realtime/authorization)
- [Securing the Data API](https://supabase.com/docs/guides/api/securing-your-api)
- [Database function privileges](https://supabase.com/docs/guides/database/functions)
- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
- [Password security](https://supabase.com/docs/guides/auth/password-security)
