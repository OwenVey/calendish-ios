# Calendish Apple design review

Reviewed October 6, 2026 against the Apple Human Interface Guidelines bundled with the apple-design skill, including its June–September 2026 updates, and Apple's current public Liquid Glass documentation.

## Summary

**Overall rating: Critical issues**, because the welcome screen fails at the largest accessibility text size. The architecture is already convincingly native: SwiftUI tabs, navigation stacks, lists, forms, system search, pickers, and toolbars. A broad visual redesign would discard good work. The next iteration should make those components behave consistently, protect people's work, and adapt to their settings.

The design thesis is a calm shared kitchen utility: find a dish, choose when to cook it, and shop together. The muted green palette suits that purpose. Let food photography and the weekly planning rhythm supply the personality while the system owns navigation and controls.

## Scope and evidence

- Reviewed every SwiftUI screen and shared component: account entry, email/password flow, household setup, recipe book, recipe detail, recipe editor, link import, photo sources, meal planning, meal picker, grocery list, grocery import review, cooking mode, and all settings screens. Also inspected app configuration, color/icon assets, and store behavior affecting UI feedback.
- Built and relaunched the current source with `./scripts/run-sim.sh` on the booted iPhone 18 Pro running iOS 27.0. Build and launch succeeded.
- Inspected welcome, email, and password screens through Device Hub's accessibility tree. Tested welcome at default and largest accessibility text sizes in dark appearance. Restored the original text setting afterward. No account was created or signed in.
- Household screens were reviewed from source because the running app was signed out. Their final rendering, VoiceOver speech, touch bounds, keyboard behavior, and iPad adaptation remain unverified. Findings below distinguish observed failures from source evidence and design judgment.
- Solid accent/on-accent contrast, calculated from the sRGB assets: **6.16:1 light**, **8.35:1 dark**. Both exceed 4.5:1. These numbers do not certify glass, gradients, photos, or all secondary text.
- Screenshots: `.build/design-review/onboarding-default-dark.png` and `.build/design-review/onboarding-ax5-dark.png`.

This is a design and interaction audit, not an App Store policy certification. The iOS 27 release-note page was reachable, but its Markdown content could not be retrieved through the web tool; no unverified version-specific redesign claims are used here.

## Critical

### 1. Welcome fails at accessibility text sizes — observed

**What:** At AX5, the logo is clipped above the screen, feature titles and descriptions truncate, and both sign-in labels become ellipses. The privacy text falls outside the visible layout. The screen uses a non-scrollable `VStack` with three 40-point minimum spacers and a fixed 42-point brand title. Source: `AccountViews.swift:9–78`.

**Why:** `typography.md › Supporting Dynamic Type`: “Make sure your app’s layout adapts to all font sizes.” [Apple Typography](https://developer.apple.com/design/human-interface-guidelines/typography).

**Fix:** Put welcome content in a `ScrollView`; allow authentication labels to wrap and controls to grow. Use a bottom safe-area action area only if it also remains usable at AX5, otherwise let actions scroll with content. Reduce decorative spacing and stack feature icons above text at accessibility sizes. Scale the brand title with a semantic style or `@ScaledMetric`. Acceptance: all information and complete action labels are reachable at AX5 on the smallest supported iPhone, in portrait and landscape.

## Improvements

### 2. High — Recipe sheets can silently discard work

**What:** Recipe editor state is local and both Cancel and swipe dismissal discard it. There is no dirty-state check, draft persistence, or dismissal protection. Meal picker has the same pattern. Source: `RecipeViews.swift:218–415`, `MealPlanView.swift:168–237`.

**Why:** `sheets.md › Mobile (iOS, iPadOS)` advises confirming swipe dismissal when there are unsaved changes. [Apple Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets).

**Fix:** Track changes against the initial draft. Route Cancel through a discard confirmation when dirty; intercept interactive dismissal and offer Keep Editing or Discard Changes. Persist longer recipe drafts locally so interruptions do not erase them. Preserve easy swipe dismissal for clean sheets.

### 3. High — Recipe details remove top-level navigation

**What:** `RecipeDetailView` explicitly hides the tab bar and substitutes a bottom action toolbar. Opening a recipe from Recipes or Meal Plan removes direct access to the other app sections. Source: `RecipeViews.swift:172`.

**Why:** `tab-bars.md › Best practices`: “Make sure the tab bar is visible when people navigate to different sections of your app.” [Apple Tab Bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars).

**Fix:** Preserve tabs on ordinary pushed recipe details. Keep Start Cooking as the primary recipe action near the title; put Plan and Add to Groceries in a small action group or menu. Let the full-screen cooking task temporarily cover tabs.

### 4. High — Import actions promise workflows that do not work

**What:** Import from a Link opens a field but cannot import. Add to Groceries offers selectable recipes but its Add button is permanently disabled. Product text describes “the next build” and implementation details. Source: `RecipeViews.swift:505–522`, `GroceryImportReviewView.swift:44–54`.

**Why:** `feedback.md › Best practices` requires explaining why commands cannot run. The misleading availability and development copy are also design judgment. [Apple Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).

**Fix:** Complete these flows before exposing them as actions. Until then, omit the entry points or clearly label their unavailable status before people invest effort. A finished import should produce an editable recipe draft; grocery review should preview actual ingredient quantities and let people confirm additions and undo them.

### 5. High — Cooking forces rotation and assumes a fixed sidebar

**What:** Cooking locks the app to landscape and initially reserves 300 points for ingredients. The step pane receives the remaining width; neither available width nor accessibility text size changes the composition. Exiting explicitly requests portrait. Source: `CookModeView.swift:17–25, 77–85`, `calendish_iosApp.swift:28–47`.

**Why:** `layout.md › Adaptability` calls for layouts based on available space; `designing-for-ios.md › Best practices` calls for seamless adaptation to orientation and Dynamic Type. [Apple Layout](https://developer.apple.com/design/human-interface-guidelines/layout).

**Fix:** Support portrait. On compact widths show the step with an Ingredients sheet or disclosure; use a side-by-side layout only when sufficient space remains for readable instructions. Collapse the sidebar at accessibility sizes. Full-screen presentation and keeping the display awake are appropriate choices to keep.

### 6. High — Sync failures interrupt without preserving or recovering the action

**What:** Every store error becomes a global “Couldn’t sync” alert with OK. Optimistic saves dismiss editors before persistence succeeds; failure refetches server data and can remove the unsaved local edit. A household lookup failure routes an existing user to household setup. Source: `ContentView.swift:35–39`, `HouseholdStore.swift:182–198, 387–402`.

**Why:** `feedback.md › Best practices`: “Consider integrating status feedback into your interface.” Critical interruption should be actionable. [Apple Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).

**Fix:** Preserve pending edits and offer Retry near the affected content. Show lightweight sync status for connectivity failures; reserve alerts for failures requiring a decision. Distinguish failed household loading from confirmed absence of membership, with a retry screen instead of Create/Join. Test recipe/photo save failures and a disconnected grocery toggle explicitly.

### 7. High — Important selection state lacks meaningful accessibility semantics

**What:** Meal picker selection is represented by a checkmark image without an explicit selected trait or value. Grocery import selection also lacks an explicit selected value. Week buttons announce the date and selection, but not Today or the meal count represented by the dot. Source: `MealPlanView.swift:136–151, 204–213`, `GroceryImportReviewView.swift:25–39`. This is source evidence; final VoiceOver speech needs testing.

**Why:** `accessibility.md › Vision`: “Describe your app’s interface and content for VoiceOver.” [Apple Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

**Fix:** Add selected traits/values to selectable recipe rows, hide redundant checkmark images, and announce “Today, 2 meals planned” on day buttons. Give repeated Edit controls contextual labels such as “Edit dinner.” Keep the good checked/unchecked values already present on grocery and ingredient rows.

### 8. High — Timers belong to the cooking view rather than the task

**What:** Timers live in view-local state. Closing or finishing cooking loses them, and the waiting task is tied to that view. There is no persistent timer model or background notification path. Source: `CookModeView.swift:11–13, 57–74, 156–164`.

**Why:** Product judgment: a kitchen timer is a promise that should survive navigating away. `feedback.md › Best practices` supports perceivable, accessible feedback; it does not mandate a particular timer architecture.

**Fix:** Own active timers outside the screen, retain end dates, and explicitly explain or confirm cancellation. Add authorized local notifications for expiration outside the foreground. A Live Activity is a useful later enhancement. Keep the existing sound, haptic, and visible expiration feedback.

### 9. High — The app icon asset contains no artwork

**What:** The AppIcon catalog declares default, dark, and tinted entries but no filenames; no icon artwork or Icon Composer asset was found. Source: `Assets.xcassets/AppIcon.appiconset/Contents.json`.

**Why:** `app-icons.md › Layer design` describes layered icons adapting to system appearance. A finished icon is also basic product craft. [Apple App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons).

**Fix:** Create a recognizable kitchen/planning mark in Icon Composer, with simple vector foreground layers and system-applied effects. Test default, dark, clear, and tinted appearances. Avoid baking in glass reflections or corner masking.

### 10. Medium — Custom controls need deliberate touch and text adaptation

**What:** Tag actions use a one-line pill with only six points of vertical padding. Meal Edit and completed-list Show/Hide are small plain text buttons. These have no explicit 44-point target; their actual hit regions need measurement. Recipe-row metadata and seven-column week labels have no accessibility-size alternative. Source: `Components.swift:51–108`, `RecipeViews.swift:297–323`, `MealPlanView.swift:41, 136–151`, `GroceryListView.swift:61`.

**Why:** `accessibility.md › Mobility`: “Offer sufficiently sized controls.” Apple's recommended iOS target is 44×44 points, with a 28×28 minimum; a smaller-than-44 target is not automatically a violation. [Apple Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

**Fix:** Give standalone pill/text actions at least 44-point interactive bounds and spacing without overlapping targets. Wrap metadata and tags at large text sizes; switch the week strip to a layout that can show complete readable dates. Measure with Accessibility Inspector rather than inferring bounds from visible text.

### 11. Medium — Custom motion does not explicitly honor Reduce Motion

**What:** Sidebar slide transitions, paged step changes, week scrolling, title fade, and grocery row movement use unconditional animations. Source: `CookModeView.swift`, `MealPlanView.swift`, `RecipeViews.swift`, `GroceryListView.swift`.

**Why:** `accessibility.md › Cognitive` asks apps to respond to Reduce Motion. [Apple Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

**Fix:** Read `accessibilityReduceMotion`; replace custom spatial transitions with immediate updates or a restrained fade. Keep system components' built-in accessibility behavior. Verify Reduce Transparency, Increase Contrast, and the iOS 27 Liquid Glass preference on custom controls; no failure in those states was measured in this review.

### 12. Medium — Form and selection flows need clearer completion and recovery

**What:** Save becomes disabled without explaining required recipe fields; meal search has no empty state; password entry has no recovery path. Household creation/join disables the form during work without showing progress. Recipe servings use a 1–1000 stepper as the only input. Source: `RecipeViews.swift:249–253, 290, 391–411`, `MealPlanView.swift:202–217`, `AccountViews.swift:134–231, 327–372`.

**Why:** `entering-data.md › Best practices`: “Dynamically validate field values.” [Apple Entering Data](https://developer.apple.com/design/human-interface-guidelines/entering-data).

**Fix:** Mark required fields and show useful inline validation; explain empty recipe search and link to creating a recipe when the book is empty. Add password reset. Show labeled progress for Create/Join. Pair a numeric servings field with increment/decrement controls. Sign in with Apple would strengthen native integration, but this audit does not claim an App Store requirement.

### 13. Medium — Toolbar treatment and sheet actions need consistency

**What:** Recipe and meal Save buttons rely on confirmation placement but do not explicitly declare a prominent style. Grocery review uses Done in the cancellation position. The inert link-import form has only Done. Source: `RecipeViews.swift:390–411, 519`, `MealPlanView.swift:220–227`, `GroceryImportReviewView.swift:53–54`.

**Why:** `toolbars.md › Actions` recommends prominence for the primary completion action. `sheets.md › Anatomy` distinguishes completing a task from dismissing without saving. [Apple Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Apple Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets).

**Fix:** Use a single prominent Save/Add action at the trailing edge and Cancel or the system Close control for dismissal. Let standard toolbar rendering supply glass; verify the resulting iOS 27 appearance before adding additional button surfaces. Large detents are suitable for the recipe editor; medium detents should be reserved for genuinely short tasks.

### 14. Medium — Groceries need editing, accessible reordering, and recovery

**What:** Items can be checked, moved, and deleted, but there is no item-edit screen or visible Edit mode. The list has `.onMove` without an EditButton, so discoverability of handles needs verification. Deletes persist immediately without undo. Meal removal also has no undo. Source: `GroceryListView.swift:30–39, 77–96`, `HouseholdStore.swift:340–344, 373–383`.

**Why:** Design judgment informed by familiar iOS list behavior and `accessibility.md › Mobility`, which calls for alternatives to gestures.

**Fix:** Offer an Edit action with system reorder handles, a row edit action for name/amount, and accessible Move Up/Down actions where appropriate. Provide undo for routine removal, preserving original IDs and ordering. Keep confirmation for bulk clearing if recovery is unavailable.

## Craft notes

**Medium — Reduce decorative repetition.** Green placeholders, tag pills, step-number circles, and feature-icon circles repeat the same emphasis across unrelated content. Keep green for selection and primary actions; make supporting metadata quiet. This is design judgment, not a claim that tinted pills violate HIG. Recipe photos and the week strip are the strongest candidates for a signature.

**Low — Treat settings as a supporting area.** The grouped profile/household layout is familiar and worth keeping. Four top-level tabs are reasonable; moving Settings behind an account button is optional product judgment, not a requirement. Keep System as the default appearance. The Light/Dark override is a user preference, not by itself a compliance failure.

**Low — Standardize product language.** Use consistent title capitalization for titles and action labels. “Planned for 4” should say “4 servings.” The household setup footer refers to “Your household,” while the setting is labeled “Household.” Remove future-build and backend terminology from all user-facing flows.

## What works

- `TabView`, `NavigationStack`, `List`, and `Form` supply the right platform foundation. Keep them.
- System search with sort/filter menus is appropriate for a recipe library; a separate Search tab is not necessary.
- Grouped settings, native sharing, PhotosPicker, file import, secure password entry, keyboard/content-type configuration, and time wheels use familiar system mechanisms.
- Recipe and grocery checklists have explicit accessibility values and sensory feedback. Decorative recipe artwork and avatars are hidden from accessibility where accompanying text conveys identity.
- Semantic foreground/background colors and separate light/dark accent assets are good choices. The solid accent contrast is strong; no palette replacement is justified by the measurements.
- Empty recipe and grocery states explain what to do next. The inline grocery-entry pattern is a good fit for quick repeated additions.
- Full-screen cooking, readable instruction type, multiple timers, and keeping the display awake match the context. Preserve those features while fixing adaptation and timer ownership.

## Platform notes and verification still needed

The app targets both iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`) with iOS 26 as its minimum. That minimum does not prevent standard SwiftUI controls from rendering with iOS 27's system design. Keep standard components and compile against the current SDK; do not imitate system glass with fixed opacity, borders, or shadows. [Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials).

On iPad, the current navigation stacks are valid, but recipe list/detail could benefit from `NavigationSplitView`. A sidebar-adaptable tab bar is optional for four sections. Test narrow and resized windows before deciding. The date popover's fixed 320-point picker and cooking's fixed sidebar need particular attention.

Before calling the whole app fully native and accessible, verify all household screens on a small iPhone and resized iPad with AX5, VoiceOver, light/dark appearance, Increase Contrast, Reduce Motion, Reduce Transparency, and the system Liquid Glass preference. Include keyboard dismissal, back gestures, sheet dismissal with changes, offline saves, failed photo import/upload, meal replacement, grocery undo, and timers when backgrounded or closed. Real-device camera, permission-denial, and timer delivery checks remain outstanding.

## Recommended sequence

1. Fix the confirmed welcome accessibility failure; add selection semantics and comfortable custom-control targets.
2. Protect drafts, preserve tabs, adapt cooking to available space, and make sync failures recoverable.
3. Complete or remove inert imports; implement timer persistence and password recovery.
4. Refine toolbar prominence, list editing/undo, iPad layouts, and app icon artwork.
5. Reduce decorative repetition and polish copy after the behavior passes the verification matrix.

No app source changes were made for this review.
