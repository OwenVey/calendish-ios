# Git workflow: releases and hotfixes

Calendish is distributed through internal TestFlight only. Accumulate work in `develop`, then merge `develop` into `main` when Owen wants a new TestFlight build.

## Builds and distribution

- The single Xcode Cloud workflow, `Internal TestFlight`, automatically archives changes to `main` and distributes them to the Family internal tester group.
- Changes to `develop` and feature branches, and pull request updates, trigger no Xcode Cloud builds. There is no PR build workflow.
- Manual starts are available for `main`. Automatic branch builds have auto-cancel enabled.
- Archives use TestFlight (Internal Testing Only) distribution preparation. App Store submission is outside this workflow.

The branch trigger reacts to any change to `main`; it does not inspect the PR's source branch. Use a release PR as the normal way to request a build.

## Merge methods

Active GitHub rulesets require PRs for both `develop` and `main`, block branch deletion and force pushes, and have no bypass actors. Pass the merge method explicitly:

- Into `develop`: use `gh pr merge --squash` for a feature branch, and `gh pr merge --merge` when bringing `main` back into `develop`. GitHub permits both methods; choosing between them is a convention.
- Into `main`: use `gh pr merge --merge`. GitHub enforces merge commits only, preserving shared history for subsequent releases.

GitHub does not restrict the source branch of PRs into `main`. Required approvals and required build, test, or lint checks are not configured. Run the repository's applicable checks before merging; the rulesets do not verify them.

## Version

Xcode Cloud supplies increasing build numbers, so leave `CURRENT_PROJECT_VERSION` alone. A new TestFlight build can keep the existing marketing version; bump it only when Owen requests a version change.

`MARKETING_VERSION` is set at the project level of `calendish.xcodeproj` (Debug and Release); all three targets inherit it. Make requested version changes there so the app and its extensions stay in step.

## Release

1. Update local refs and review the changes in `develop` since the last release. If Owen requested a version change, make it on `chore/release-<version>` from `develop` and squash-merge its PR into `develop` first.
2. Open a PR from `develop` into `main` titled `chore: release TestFlight build` (include the version if changed), listing the PRs merged since the last release. Merge it with a merge commit.
3. Verify that Xcode Cloud starts `Internal TestFlight` for the resulting `main` commit, succeeds, and distributes the new build to Family in App Store Connect.

Done when the release PR is merged, `main` contains the intended release tree, and the new build is available to Family in TestFlight. If `develop` has advanced during the build, it may already contain work for the next release. Report build or distribution failures as an incomplete release.

## Hotfix

1. Branch `hotfix/…` off `main` when an urgent fix must ship ahead of pending work in `develop`. Bump the marketing version only if Owen requests it.
2. PR it into `main` and merge with a merge commit.
3. Verify the resulting TestFlight build as in the release steps.
4. PR `main` into `develop` and merge with a merge commit so the fix reaches `develop`. This merge triggers no build.

Done when both PRs are merged and the hotfix build is available to Family in TestFlight.
