# Household notifications

Members choose each kind of alert in **Calendish → Settings → Notifications** on each iPhone. Each one starts off, is remembered separately for each account on that installation, and requires iOS notification permission. Nobody receives alerts about their own changes.

| Setting | Alert | Tapping it |
| --- | --- | --- |
| **New recipes** | “Owen added a recipe” with the recipe title, when a member saves a **new shared recipe**. Private recipes, recipe edits, sharing older recipes, and copies preserved during household moves stay quiet. | Opens the recipe after checking the signed-in account, current household, and current recipe access. |
| **Grocery additions** | “Owen added 4 items to groceries” with up to three item names. Additions one person makes within two minutes of their last addition share one alert, sent at most ten minutes after the first. Items removed before it sends are not counted. Checking, editing, and reordering items stay quiet. | Opens the Groceries tab. |
| **Household members** | “Sam joined your household”, to other members when someone joins with an invite code. “You were removed from Vey Household”, to a member the owner removes. Starting, leaving, or moving households, and deleting an account, stay quiet. | Opens Settings for a join. A removal opens the app to the person’s new household. |

The setup prompt after starting or joining a household turns on all three. Turning on any alert also turns on **Household members** unless the person turned it off before. Installations that had turned on recipe alerts before the other kinds existed keep them on and get membership alerts too.

## Finish Apple setup

The app capability, hosted migration, queue, retry schedule, worker, and worker authentication are configured for the current project (`wgtrbwbfazdizkevtwfp`). Live delivery still needs an Apple APNs signing key. No Apple key is included in the app or repository.

1. In **Xcode → Settings → Accounts**, sign in with the Apple account for team `Q97ES87SKW`. The physical-device build currently fails because Xcode has no account and its cached profile lacks Push Notifications. Then sign in to [Apple Developer](https://developer.apple.com/account/resources/identifiers/list). Under **Certificates, Identifiers & Profiles → Identifiers**, select `owenvey.calendish` and check **Push Notifications**. The Xcode target already declares this capability; automatic signing can enable it and refresh the development profile when `./scripts/run-device.sh` builds. See [Apple’s capability instructions](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/).
2. Under **Keys**, add a key named “Calendish notifications”, enable **Apple Push Notification service (APNs)**, and choose **Configure**. Select the environment and key scope. For a topic-specific key, include `owenvey.calendish`. Use **Sandbox** for the development build installed by `run-device.sh`; use **Production** for TestFlight and App Store builds. If Apple requires separate keys, create a related key for the other environment. See [Apple’s current key creation instructions](https://developer.apple.com/help/account/keys/create-a-private-key/).
3. Download the `.p8` file and keep it securely outside this repository. Record its **Key ID**. Confirm your **Team ID** in Apple Developer membership details; this Xcode project uses `Q97ES87SKW`. Apple only allows downloading a key once.
4. From the repo, upload the sandbox key with the helper below. It validates the key, uploads it using a temporary file with restricted permissions, deletes that file, and redeploys the worker. The Supabase CLI must be signed in and linked to Calendish. Node 22.18+ is required for the TypeScript module used by the helper.

   ```sh
   node scripts/configure-apns.mjs /absolute/path/to/AuthKey_KEYID.p8 KEYID Q97ES87SKW sandbox
   ```

   Upload a separate production key with the last argument `production`. For an existing key authorized for **both** environments, use `both` instead. Environment-specific keys take precedence over a shared key.
5. Rebuild the iPhone app if its provisioning profile changed: `./scripts/run-device.sh`. On two devices signed in as different members of the same household, turn on **New recipes** and allow notifications. Put one app in the background and add a **new shared recipe** on the other device. The recipient should receive an alert; tap it to check that the right recipe opens. Repeat with a private recipe to confirm it stays quiet.

The simulator’s injected notifications verify presentation and routing, but do not prove APNs delivery. A real delivery test remains necessary after the signing key is uploaded.

## Backend behavior

`push_devices` associates an opaque installation ID and APNs token with a signed-in user, a live Auth session, and that installation’s opt-in for each kind of alert. Client-accessible RPCs validate the caller; app clients cannot read device tokens, events, or deliveries. Signing out revokes the device association before ending the session. Revoked Auth sessions and deleted accounts cascade-remove associations and queued deliveries.

Every alert is a `push_events` row with a `kind` (`recipe`, `groceries`, `member_joined`, or `member_removed`) and one `push_deliveries` row per opted-in recipient device. Triggers create them:

- A recipe insert adds one event per recipe. Household-preservation copies have no personal owner and are excluded.
- A grocery insert, per statement, adds the items to the person’s open grocery event for that household or starts one. `push_event_groceries` links the items. Inserts without a signed-in person, such as server-side copies, are excluded.
- A membership insert into a household that already has other members is a join. A membership delete by the household’s owner, of someone else, is a removal; the household name is saved because the removed person can no longer read it.

The worker rechecks the device’s account and preference immediately before sending, and that the actor and recipient are still in the household. A removal requires the recipient to still be outside it. Recipe alerts also recheck sharing, and grocery alerts count only items still on the list. Alerts use current titles, item names, and display names.

The Edge Function, Vault entries, and worker secret keep their original `recipe` names so existing deployments don’t need new secrets; they deliver every kind of household alert.

A private server secret authenticates the Edge Function. The database reads its endpoint and secret from Vault (`recipe_push_url` and `recipe_push_worker_secret`). The matching Edge Function secret is `RECIPE_PUSH_WORKER_SECRET`. Only the service role can claim, prepare, or acknowledge deliveries. The worker sends directly to APNs using HTTP/2 and an ES256 provider token; no third-party notification service is required.

Immediate database wake-ups normally start delivery after a recipe saves or membership changes. Grocery alerts wait for their window to close and are sent by the next cron run. Cron retries every minute. Concurrent workers use row locks and per-attempt leases. Temporary failures retry with backoff, with at most six attempts and a one-hour alert lifetime. Invalid APNs tokens are removed. Completed event history is deleted after seven days. Retries use a stable APNs ID and collapse ID to reduce duplicate presentation; delivery is best effort, and a lost acknowledgement can still cause a retry after Apple accepted a notification.

Worker secrets:

| Name | Purpose |
| --- | --- |
| `APNS_TEAM_ID` | Apple Developer Team ID |
| `APNS_SANDBOX_KEY_ID`, `APNS_SANDBOX_PRIVATE_KEY` | Development signing credentials |
| `APNS_PRODUCTION_KEY_ID`, `APNS_PRODUCTION_PRIVATE_KEY` | TestFlight/App Store signing credentials |
| `APNS_KEY_ID`, `APNS_PRIVATE_KEY` | Optional fallback for a key authorized for both environments |
| `RECIPE_PUSH_WORKER_SECRET` | Dedicated server authentication, also stored in Vault |

The worker only claims deliveries for environments with configured credentials. Missing Apple credentials return HTTP 503 before claiming work. Ordinary calls without the worker secret return HTTP 401.

For another Supabase project, deploy the migration and function, generate a fresh worker secret, put that same value in Edge Function Secrets and Vault, and set the Vault endpoint to that project’s `https://PROJECT_REF.supabase.co/functions/v1/household-recipe-push`. The migration creates the minute-by-minute retry and daily cleanup jobs. [Supabase documents this Cron/pg_net/Vault setup](https://supabase.com/docs/guides/functions/schedule-functions).

## Verification

```sh
node --test scripts/test-recipe-push-worker.mjs
node scripts/test-household-notifications.mjs
./scripts/test-household-workflow.sh
./scripts/format.sh
./scripts/lint.sh
./scripts/run-sim.sh
./scripts/run-device.sh
```

The live backend suite creates disposable users and households, tests registration, isolation, opt-outs, membership changes, grocery batching, join and removal alerts, leases, retries, invalid tokens, and revoked sessions, and removes its fixtures. It never calls APNs or sends real notifications. The native workflow suite also checks payload validation and registration encoding. Focused UI tests in `HouseholdUITests` verify opening the recipe, explaining a missing recipe, ignoring another account’s alert, and opening the grocery list. Run those four tests with `scripts/test-household-ui.sh` after building the workflow fixture app.
