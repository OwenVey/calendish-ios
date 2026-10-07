# Calendish

A shared recipe book, meal planner, and grocery list for your household. Built with SwiftUI for iOS 26 and backed by Supabase.

## Features

- **Recipes.** A searchable recipe book with photos, favorites, tag filters, sorting, recipe details, a manual recipe form, and a full-screen cook mode with step-by-step instructions, ingredient checkmarks, and timers.
- **Recipe photos.** Take a photo with the camera, or choose one from the photo library, Files, or the clipboard.
- **Meal Plan.** A swipeable week strip and calendar with breakfast, lunch, and dinner slots. Pick recipes, set servings, and move or remove meals.
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

```
calendish-ios/
├── calendish_iosApp.swift        App entry point
├── ContentView.swift             Tab bar: Recipes, Meal Plan, Groceries
├── HouseholdStore.swift          Auth, household data, saving, and Realtime sync
├── Backend.swift                 Supabase client and row mapping
├── Models.swift                  Recipe, meal, and grocery models
├── RecipeViews.swift             Recipe book, detail, and forms
├── RecipePhotos.swift            Photo picking, uploads, and caching
├── CookModeView.swift            Step-by-step cooking view
├── MealPlanView.swift            Week strip and meal slots
├── GroceryListView.swift         Grocery checklist
├── GroceryImportReviewView.swift Review screen for imported groceries
├── AccountViews.swift            Sign-in and household setup
├── SettingsView.swift            Household and account settings
└── Components.swift              Shared UI pieces
supabase/
├── config.toml                   Auth and project settings
└── migrations/                   Schema and Row Level Security policies
scripts/
└── run-sim.sh                    Build and relaunch in the simulator
```

## Backend

Every row belongs to a household, and Row Level Security limits access to that household's members. Recipe photos live in a private Storage bucket (`recipe-images`) under a folder for each household, with the same members-only rule. `HouseholdStore` applies edits on screen right away and saves them in the background. Other members' changes arrive over a private household Realtime Broadcast channel, and the app catches up after reconnecting or returning to the foreground. Meal moves and grocery reordering use atomic database RPCs. Household collections use keyset pagination to avoid Data API row limits.

SwiftUI previews use `HouseholdStore.preview()`, which has sample data and makes no network calls.

### Database changes

The Supabase project is connected to this repo through the Supabase GitHub integration. To change the schema:

1. Add a migration under `supabase/migrations/` (`supabase migration new <name>`).
2. Test it locally with `supabase start` and `supabase db reset`.
3. Merge to `main`. Supabase applies new migrations to the production project.

Local Auth settings such as redirect URLs live in `supabase/config.toml`; hosted Auth settings must be reviewed and applied separately. Database migrations do not update hosted Auth configuration.

See [the Supabase review](docs/supabase-review.md) for the access model and verified behavior. Run `./scripts/test-grocery-sync.sh` for local grocery merge tests. With the Supabase CLI authenticated to this project, `node scripts/test-grocery-realtime.mjs` tests live syncing, household isolation, atomic RPCs, pagination, and private Storage using disposable fixtures. Use a scoped CLI token for automated runs. Administrative test keys stay in memory and are never shipped in the app.

## Roadmap

- Sign in with Apple
- Password reset
- Offline support
- Recipe import from a URL
- Adding a recipe's ingredients to the grocery list
- Deleting recipes
- Editing and removing individual grocery items
