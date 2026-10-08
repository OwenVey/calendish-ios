# Household and recipe ownership validation

Issue: [#1](https://github.com/OwenVey/calendish-ios/issues/1). Validated October 7, 2026.

## Checks

- `node scripts/test-household-moves.mjs`: passed. Disposable authenticated users exercise solo/invited onboarding, invalid/current invitations, moves, removal, transfer, sharing permissions, private saves, retained copies, saved meals, photo access, household deletion, Realtime revocation, simultaneous departures, and unshare/move races. Fixture cleanup passed.
- `node scripts/test-grocery-realtime.mjs`: passed. Two-client Broadcast syncing, access denial, reconnect recovery, recipe edits, atomic meal/grocery operations, pagination, and Storage isolation. Fixture cleanup passed.
- `./scripts/test-household-workflow.sh`: passed. Production HouseholdStore with an injected Supabase HTTP client verifies onboarding, invitation continuation, rejected moves, lost-response recovery, stale household reads, sign-out during entry, late copy responses, saved meal versions, and Swift encoding when moving a saved version.
- `./scripts/test-household-ui.sh`: all seven cases passed, with the final dialog case rerun individually after correcting selectors for iOS 27 popover confirmations. Covers name-only onboarding, invite review/cancellation, ownership filters/permissions, sharing/deletion explanations, bulk-save default, automatic successor explanation, manual transfer, and saved-meal detail. Uses a separate fixture app.
- Grocery synchronization/workflow, aisle, recipe observation, grocery review, ingredient parsing/scaling/conversion, and recipe import regression scripts: passed.
- `./scripts/test-grocery-search-ui.sh`: passed all three search open/close cycles.
- `git diff --check`: passed.

The existing cook-mode UI suite was not run: its required “Sheet pan lemon chicken” recipe is absent from the simulator account. The cooking implementation is unchanged; the new planned-meal UI check verifies that saved content reaches recipe details.

The linked database security advisor reports only the existing Auth leaked-password-protection setting warning, with no database security warnings.

## Deployment

All four new database migrations were applied to the linked project. The app was built, installed, and relaunched with `./scripts/run-sim.sh`, followed sequentially by `./scripts/run-device.sh` on Owen’s iPhone. Both succeeded.

## Review

### Standards

No documented-standard violations or material refactoring findings remain. The review identified account/session publication and leave-retry issues; these were corrected and exercised by workflow/UI checks.

### Spec

Review findings about private bulk saves on join, solo-household retention, concurrent sharing/moves, and stale session entry were corrected. The saved-version move encoding issue was reproduced with a failing client test before its fix. No material implementation findings remain; the cook-mode fixture limitation above remains a verification gap.
