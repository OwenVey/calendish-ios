# calendish-ios

After making code changes, run `./scripts/run-sim.sh` to build and relaunch the app in the booted iOS simulator so the user can see the changes immediately.

Also run `./scripts/run-device.sh` after making code changes to build, install, and relaunch the app on Owen’s physical iPhone. The script defaults to `Owen’s iPhone`; override its device name with the first argument or `IPHONE_DEVICE` environment variable. Keep simulator and device builds sequential. If the iPhone is disconnected, locked, or deployment fails, report that the phone was not updated and why; do not claim it has the latest changes. The user needs to keep the phone reachable via USB or paired Wi-Fi and unlocked for deployment.

Before building, run `./scripts/format.sh` to apply SwiftFormat, then `./scripts/lint.sh` to check SwiftFormat and SwiftLint. Fix any lint errors before finishing. Don't add new warnings. Both tools are pinned in `BuildTools/Package.swift` and built by SwiftPM on first use. Don't install them with Homebrew. The rules live in `.swiftformat` and `.swiftlint.yml`. A pre-commit hook in `.githooks/` formats and lints staged Swift files. Run `./scripts/install-hooks.sh` once per clone to enable it.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `OwenVey/calendish-ios` (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `GLOSSARY.md` plus `docs/adr/`, created lazily. See `docs/agents/domain.md`.
