# Git workflow: releases and hotfixes

Every push to `develop` and `main` builds in Xcode Cloud and uploads to TestFlight: `develop` for internal testers, `main` for the App Store. Pull requests only build and test.

## Merge methods

GitHub rulesets enforce these, so a wrong method fails the merge:

- Into `develop`: squash a feature branch; use a merge commit when bringing `main` back into `develop`.
- Into `main`: merge commit only. A squash would give `main` commits `develop` lacks, and every later release would conflict.

## Version

`MARKETING_VERSION` is set once, at the project level of `calendish.xcodeproj` (Debug and Release); all three targets inherit it. Change it there, not on a target, so the app and its extensions stay in step. App Store Connect needs a higher version for each App Store release. Build numbers come from Xcode Cloud, so leave `CURRENT_PROJECT_VERSION` alone.

## Release

1. Branch `chore/release-<version>` off an up-to-date `develop`. Bump the minor version (1.1 → 1.2) unless the user names one. Squash-merge a PR titled `chore: release <version>` into `develop`.
2. Open a PR from `develop` into `main` titled `Release <version>`, listing the PRs merged since the last release. Merge it with a merge commit.

Done when `main` and `develop` point at the same tree and the PR is merged.

## Hotfix

1. Branch `hotfix/…` off `main`. Fix, and bump the patch version (1.2 → 1.2.1).
2. PR it into `main` and merge with a merge commit.
3. PR `main` into `develop` and merge with a merge commit so the fix reaches `develop`.

Done when both PRs are merged.
