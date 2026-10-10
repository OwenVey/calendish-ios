# Calendish

A shared recipe book, meal planner, and grocery list for your household. Built with SwiftUI for iOS 26 and backed by Supabase.

## Features

- **Recipes.** A searchable recipe book with photos, favorites, tag filters, sorting, recipe details, a manual recipe form, and a full-screen cook mode with step-by-step instructions, ingredient checkmarks, and timers.
- **Recipe photos.** Take a photo with the camera, or choose one from the photo library, Files, or the clipboard.
- **Meal Plan.** A scrolling list of days. Add any number of recipes to a day, set servings, and move or remove meals.
- **Groceries.** A shared checklist with a remaining-item count, grouping by recipe, reordering, and bulk clearing.
- **Households.** Sign in with Google or email, then create a household or join one with an invite code. Everyone in the household sees the same data, and changes sync live.
- **Native design.** Liquid Glass tabs, toolbars, and sheets, with semantic colors for light and dark mode.

## Tech stack

| Layer    | Choice                                                                 |
| -------- | ---------------------------------------------------------------------- |
| UI       | SwiftUI, iOS 26+                                                       |
| Backend  | [Supabase](https://supabase.com) (Postgres, Auth, Realtime)            |
| Packages | [supabase-swift](https://github.com/supabase/supabase-swift), [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) |

## Getting started

Requirements: Xcode 27 or later, and the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) if you plan to change the database.

1. Clone the repo and open `calendish-ios.xcodeproj`.
2. Let Xcode resolve the Swift packages.
3. Run the `calendish-ios` scheme on an iPhone simulator.

To build and relaunch from the terminal in the booted simulator:

```sh
./scripts/run-sim.sh
```

The app points at the hosted Supabase project (`wgtrbwbfazdizkevtwfp`). The publishable key in `Backend.swift` is meant to ship in the app; Row Level Security decides what each signed-in user can reach.

## Project structure

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
│   ├── Account/                 Sign-in, profiles, household setup and moves
│   └── Settings/                Settings screens and supporting controls
├── UI/                          Reusable styles, controls, layout, interface copy
│   └── Photos/                  Shared photo-picking controls
├── Data/                        HouseholdStore, backends, subscriptions
│   ├── Records/                 Database row representations
│   └── Parameters/              Backend operation inputs
├── Assets.xcassets/              App colors and images
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
docs/                            Feature notes, research, reviews, agent guidance
└── adr/                         Architecture decisions
```

Keep views, models, and behavior together in the feature that owns them, even when
another feature uses them. Put reusable UI in `UI/` and backend plumbing in `Data/`.
`Shared/` and `CookingActivityShared/` are for code compiled into multiple targets.
Add subfolders when a feature has a distinct cluster of related files rather than
creating a separate folder for every type of Swift declaration.

Xcode uses filesystem-synchronized folders, so files under the app and extension
roots are discovered automatically. When moving app or test files, also update
`scripts/support/sources.zsh`, explicit paths in the regression scripts, and the
app-entry-point exclusion in `scripts/support/household-test-project.py`.

## Backend

Every person has one current household, provisioned automatically after sign-up or joined from an invitation. Groceries, planned meals, and household-owned recipes belong to that household. Personal recipes belong to their creator and follow them between households; sharing gives the current household access to the original. Only its owner edits a personal original, while all members can edit household recipes. Ending sharing or deleting a shared original retains an independent household copy. Saved personal copies start private.

Row Level Security enforces these ownership boundaries for database rows and recipe photos. Copies and planned meals keep access to photos they still use. Planned meals capture a recipe version and serving count; later recipe edits do not change them or groceries already added. Household moves, ownership transfer, recipe retention, and optional private bulk saves use authenticated atomic RPCs.

`HouseholdStore` applies edits on screen immediately and saves them in the background. Private household and personal Realtime channels notify other devices; authoritative reads catch up after reconnecting. Session guards prevent late responses from publishing data into another household or account. Collections use keyset pagination to avoid Data API row limits.

SwiftUI previews use `HouseholdStore.preview()`, which has sample data and makes no network calls.

### Database changes

The Supabase project is connected to this repo through the Supabase GitHub integration. To change the schema:

1. Add a migration under `supabase/migrations/` (`supabase migration new <name>`).
2. Test it locally with `supabase start` and `supabase db reset`.
3. Merge to `main`. Supabase applies new migrations to the production project.

Local Auth settings such as redirect URLs live in `supabase/config.toml`; hosted Auth settings must be reviewed and applied separately. Database migrations do not update hosted Auth configuration.

See [the Supabase review](docs/supabase-review.md) for the access model and verified behavior. Run `./scripts/test-grocery-sync.sh` for local grocery merge tests. With the Supabase CLI authenticated to this project, `node scripts/test-grocery-realtime.mjs` tests live syncing, household isolation, atomic RPCs, pagination, and private Storage using disposable fixtures. Use a scoped CLI token for automated runs. Administrative test keys stay in memory and are never shipped in the app.

### Household regression checks

- `node scripts/test-household-moves.mjs`: authenticated multi-user ownership, membership, photos, saved meals, and concurrency checks using disposable hosted fixtures.
- `./scripts/test-household-workflow.sh`: builds a separate simulator app from production sources and runs the store through a controlled HTTP client, including lost responses, delayed reads, sign-out races, and invitation continuation.
- `./scripts/test-household-ui.sh`: runs the household UI suite against that simulator fixture app. Run the workflow script first to build and install it. The fixture does not alter your signed-in app’s data.

## Roadmap

- Sign in with Apple
- Password reset
- Offline support
- Recipe import from a URL
- Adding a recipe's ingredients to the grocery list
- Deleting recipes
- Editing and removing individual grocery items
