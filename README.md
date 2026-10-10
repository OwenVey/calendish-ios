<div align="center">

<img src="design/readme/logo.svg" width="128" height="128" alt="Calendish app icon">

# Calendish

**Recipes, meal plans, and groceries for your whole household.**

Save recipes from anywhere, plan the week together, shop from one live list, and cook hands-free.

[![iOS 26+](https://img.shields.io/badge/iOS-26%2B-0E9F6E?style=flat-square&logo=apple&logoColor=white)](#getting-started)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-0A84FF?style=flat-square&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Supabase](https://img.shields.io/badge/Supabase-Postgres%20%C2%B7%20Auth%20%C2%B7%20Realtime-3ECF8E?style=flat-square&logo=supabase&logoColor=white)](https://supabase.com)

[Features](#features) · [Getting started](#getting-started) · [Architecture](#architecture) · [Backend](#backend) · [Testing](#testing) · [Docs](#documentation)

</div>

---

## Features

### 📖 Recipes

- **Recipe book** with grid and list layouts, search across titles, ingredients, and tags, separate category and tag filters, and **All / Mine / Household** scopes.
- **Sorting** by recently added, title, rating, or when a recipe was last cooked or planned.
- **Import from anywhere.** Paste or share a web link, Instagram, TikTok, or YouTube post, plain text, photos, a PDF, or a document scan. Imports always open as an editable draft before saving, and processing stays on the device.
- **Reviews and history.** Each member keeps a star rating and note, and Cooked History tracks every day a recipe was cooked or planned.
- **Personal and household recipes.** Personal recipes follow their owner between households, can be shared with the household or kept private, and others can save their own copies.
- **Scale servings** in recipe details and Cook Mode; planned meals open at their planned serving count.
- **Drafts** are kept on the device until you save or discard them.

### 🍳 Cook Mode

- Full-screen, step-by-step instructions with an ingredient panel and checkmarks.
- **Timers** detected from each step, with notifications or alarms that survive leaving the app.
- **Live Activity** on the Lock Screen and in the Dynamic Island, with controls to move between steps and manage timers.
- **Hands-free mode.** Say "next", "back", or "start timer". Speech recognition runs entirely on the device.

### 🗓️ Meal Plan

- A scrolling list of days with a configurable week start. Pull down to reach earlier weeks.
- Add any number of recipes to a day with their own serving counts, plus free-text notes like "Leftovers" or "Eating out".
- Drag meals between days, or select several and remove them at once.

### 🛒 Groceries

- One shared checklist that syncs live across the household.
- **Add from recipes or planned meals.** Review each ingredient, adjust servings, and skip what you already have. Matching items are merged, so "3 onions" covers both the stew and the tacos.
- **Aisle grouping** using on-device Apple Intelligence, or group by recipe.
- Checked items can be cleared by hand or automatically.
- **Add with Siri or Shortcuts.** On iOS 27, say "Add apples to Calendish" and Siri adds them without opening the app.

### 🏠 Households

- Sign in with Google or email. New accounts get their own household automatically.
- Invite people with a code, transfer ownership, remove members, or move to another household.
- Profile photos, and account deletion from Settings.

### ✨ Native design

Liquid Glass tabs, toolbars, and sheets; semantic colors for light and dark mode; Dynamic Type layouts; and a share extension for importing recipes from other apps.

## Getting started

### Requirements

- Xcode 27 or later
- An iOS 26 simulator or device
- The [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), only if you plan to change the database

### Run the app

1. Clone the repo and open `calendish-ios.xcodeproj`.
2. Let Xcode resolve the Swift packages.
3. Run the `calendish-ios` scheme.

Or build and relaunch from the terminal:

```sh
./scripts/run-sim.sh                    # booted iOS simulator
./scripts/run-device.sh "Your iPhone"   # paired physical device
```

The app points at the hosted Supabase project (`wgtrbwbfazdizkevtwfp`). The publishable key in `Backend.swift` is meant to ship in the app; Row Level Security decides what each signed-in user can reach.

SwiftUI previews use `HouseholdStore.preview()`, which has sample data and makes no network calls.

## Architecture

| Layer          | Choice                                                                                                                                  |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| UI             | SwiftUI on iOS 26, Swift 6                                                                                                              |
| Backend        | [Supabase](https://supabase.com): Postgres, Auth, Realtime, and Storage                                                                 |
| Packages       | [supabase-swift](https://github.com/supabase/supabase-swift), [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS)            |
| On-device      | Foundation Models, Speech, Vision, VisionKit, and PDFKit                                                                                |
| System surface | ActivityKit and WidgetKit (Live Activity), App Intents, and a share extension                                                           |

### Targets

| Target                     | Purpose                                                    |
| -------------------------- | ---------------------------------------------------------- |
| `calendish-ios`            | The app                                                    |
| `ShareExtension`           | Import recipes shared from other apps                       |
| `CookingActivityExtension` | Cook Mode Live Activity and Dynamic Island                 |

### Project structure

```text
calendish-ios/
├── App/                         Entry point, root navigation, links, preferences
├── Features/
│   ├── Recipes/                 Recipe book, detail, editing, reviews, history
│   │   └── Import/              Links, text, photos, scans, PDF, social posts
│   ├── Cooking/                 Cook mode, sessions, ingredients, timers
│   │   └── HandsFree/           Speech recognition and spoken commands
│   ├── MealPlan/                Planned meals, notes, days, meal selection
│   ├── Groceries/               Checklist, aisles, import review, merging, sync
│   │   └── Siri/                Siri, Shortcuts, and Spotlight grocery adds
│   ├── Account/                 Sign-in, profiles, household setup and moves
│   └── Settings/                Settings screens and supporting controls
├── UI/                          Reusable styles, controls, layout, interface copy
│   └── Photos/                  Shared photo-picking controls
├── Data/                        HouseholdStore, backends, subscriptions
│   ├── Records/                 Database row representations
│   └── Parameters/              Backend operation inputs
├── Assets.xcassets/             App colors and images
├── Info.plist
└── calendish-ios.entitlements
ShareExtension/                  Share extension target
Shared/                          Code shared by the app and share extension
CookingActivityExtension/        Live Activity extension target
CookingActivityShared/           Code shared by the app and Live Activity target
tests/                           Account, Cooking, Data, Groceries, Recipes
supabase/                        Backend configuration and database migrations
scripts/                         Build, deployment, and regression checks
└── support/                     Test source groups and simulator harness builder
design/                          App icon source (Icon Composer) and README art
docs/                            Feature notes, research, reviews, agent guidance
└── adr/                         Architecture decisions
```

Keep views, models, and behavior together in the feature that owns them, even when another feature uses them. Put reusable UI in `UI/` and backend plumbing in `Data/`. `Shared/` and `CookingActivityShared/` are for code compiled into multiple targets. Add subfolders when a feature has a distinct cluster of related files rather than creating a separate folder for every type of Swift declaration.

Xcode uses filesystem-synchronized folders, so files under the app and extension roots are discovered automatically. When moving app or test files, also update `scripts/support/sources.zsh`, explicit paths in the regression scripts, and the app-entry-point exclusion in `scripts/support/household-test-project.py`.

## Backend

Every person has one current household, provisioned automatically after sign-up or joined from an invitation. Groceries, planned meals, and household-owned recipes belong to that household. Personal recipes belong to their creator and follow them between households; sharing gives the current household access to the original. Only its owner edits a personal original, while all members can edit household recipes. Ending sharing or deleting a shared original retains an independent household copy. Saved personal copies start private.

Row Level Security enforces these ownership boundaries for database rows and recipe photos. Copies and planned meals keep access to photos they still use. Planned meals capture a recipe version and serving count; later recipe edits do not change them or groceries already added. Household moves, ownership transfer, recipe retention, and optional private bulk saves use authenticated atomic RPCs.

`HouseholdStore` applies edits on screen immediately and saves them in the background. Private household and personal Realtime channels notify other devices; authoritative reads catch up after reconnecting. Session guards prevent late responses from publishing data into another household or account. Collections use keyset pagination to avoid Data API row limits.

### Database changes

The Supabase project is connected to this repo through the Supabase GitHub integration. To change the schema:

1. Add a migration under `supabase/migrations/` (`supabase migration new <name>`).
2. Test it locally with `supabase start` and `supabase db reset`.
3. Merge to `main`. Supabase applies new migrations to the production project.

Local Auth settings such as redirect URLs live in `supabase/config.toml`; hosted Auth settings must be reviewed and applied separately. Database migrations do not update hosted Auth configuration.

## Testing

Swift checks compile production sources with focused tests from `tests/`. UI checks drive the app installed in the booted simulator.

| Area       | Command                                                                                                                                         |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Recipes    | `test-recipe-import.sh`, `test-recipe-import-ui.sh`, `test-recipe-draft.sh`, `test-recipe-observation.sh`, `test-recipe-stats.sh`, `test-cooked-history.sh` |
| Cooking    | `test-hands-free-cooking.sh`, `test-cook-mode-ui.sh`                                                                                            |
| Groceries  | `test-grocery-sync.sh`, `test-grocery-import-review.sh`, `test-grocery-aisles.sh`, `test-grocery-search-ui.sh`, `test-spoken-grocery-add.sh`      |
| Households | `test-household-workflow.sh`, then `test-household-ui.sh`                                                                                       |

All commands live in `scripts/`. `test-household-workflow.sh` builds a separate simulator app from production sources and runs the store through a controlled HTTP client, covering lost responses, delayed reads, sign-out races, and invitation continuation. `test-household-ui.sh` runs against that fixture app, which does not alter your signed-in app's data.

### Live backend checks

With the Supabase CLI authenticated to this project, these scripts create disposable users and households, then remove them:

- `node scripts/test-grocery-realtime.mjs`: live syncing, household isolation, atomic RPCs, pagination, and private Storage.
- `node scripts/test-household-moves.mjs`: onboarding, ownership, membership, photos, saved meals, and concurrency.
- `node scripts/test-profile-photos.mjs`: avatar persistence and private Storage access.

Use a scoped CLI token for automated runs. Administrative test keys stay in memory and are never shipped in the app.

## Documentation

- [`GLOSSARY.md`](GLOSSARY.md): the domain language used across the app and code
- [`docs/adr/`](docs/adr): architecture decisions, including recipe ownership and on-device processing
- [`docs/supabase-review.md`](docs/supabase-review.md): the access model and verified backend behavior
- [`docs/feature-audit.md`](docs/feature-audit.md): product review and improvement priorities
- [`docs/ui-copy-style.md`](docs/ui-copy-style.md): interface writing guidelines

## Roadmap

- Sign in with Apple
- Offline shopping with queued changes
- Undo for grocery clearing and meal changes

Ideas and bugs are tracked in [GitHub Issues](https://github.com/OwenVey/calendish-ios/issues).

<div align="center">
<br>
<img src="design/readme/logo.svg" width="32" height="32" alt="">
<br>
<sub>Made for households that cook together.</sub>
</div>
