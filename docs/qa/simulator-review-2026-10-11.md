# Simulator review fixes — October 11, 2026

The original exploratory review used T3 Code on iPhone 18 Pro Max, iOS 27. These changes address its eight findings and the invalid-link recovery observation.

| Finding | Resolution | Verification |
| --- | --- | --- |
| Search disappears in Grid or after display changes | Stable recipe-book container and explicit always-visible navigation search placement in Recipes and Groceries. | T3 Grid search visible; automated layout/tab regression passed. |
| Rating buttons all named Favorite | Each button names its star count, exposes selection, and explains clearing. The group retains the current rating and adjustable action. | T3 exposes Rate 1 star through Rate 5 stars; hardware VoiceOver speech pending. |
| Largest text breaks import header and Settings values | Import header stacks; a native multiline text editor scrolls within a bounded area at accessibility sizes. Settings choices stack with wrapping values and native selection menus. Native Paste control scales through accessibility1 to avoid its label clipping at larger sizes; surrounding text scales fully. | T3 screenshots at accessibility-extra-extra-extra-large show readable header, Paste, Import and Device setting. |
| Grocery paste fields seem absent from accessibility snapshot | XCTest confirmed existing editable TextView/TextFields, contents, edits and deletion before changes. Added explicit accessibility values to the input and review fields. | Grocery review regression passed before and after changes, including real field values, edits and deletion. T3 snapshots are not a complete substitute for XCTest or VoiceOver. |
| Earlier-step timer disappears in Cook Mode | Persistent timer menu shows countdown across steps and offers jump to step, pause/resume, add a minute and cancel for each recipe timer. | T3 started step-one timer, advanced to step two and canceled it from the persistent menu. Automated regression passed. |
| New recipe saves invented 30-minute duration | New manual drafts begin with unspecified zero times; the editor says Not set, and recipe cards/rows/details omit unspecified times. Existing/imported times are preserved. | Recipe draft lifecycle regression failed with old defaults and passed after the fix, including submitted recipe and existing-time preservation. |
| Empty Mine scope gives search advice | Scoped empty state invites writing/importing and explains Save to my collection. | T3 verified the copy and both creation actions in empty Mine. |
| Shortcuts shows calendish-ios | App product name is Calendish; simulator and device install scripts use the renamed product. | Built CFBundleName and T3 system Shortcuts label both read Calendish. |
| Invalid link silently changes to text import | Typed invalid link remains in its form with a recovery error above the input; text and paste transfers retain their explicit routing. A native TextEditor exposes the Recipe text input as an editable control with a stable label. | Automated regression passed. |

Validation so far:

- `./scripts/test-recipe-draft.sh`: PASS. The added unspecified-time regression was first observed failing on the old defaults.
- `./scripts/test-recipe-import-ui.sh`: all five UI tests passed, covering ingredients-only and instructions-only imports, invalid-link recovery, rating labels and timers across steps, and search across layouts/tabs.
- `./scripts/format.sh`, `./scripts/lint.sh`, `git diff --check`, and shell syntax checks: passed. Existing lint/compiler warnings remain; no new warnings were introduced.
- `./scripts/test-grocery-search-ui.sh`: both UI tests passed, including paste review and three search dismissal cycles.
- `./scripts/run-sim.sh`: built, installed and relaunched the final app. T3 confirmed the final largest-text editor layout, both Not set duration fields, and search after restoring standard text size.
- `./scripts/run-device.sh`: built the final app, installed Calendish.app on Owen’s iPhone and successfully relaunched `owenvey.calendish-ios`.

 The UI regressions canceled their imported drafts and timers and discarded the pasted grocery list. No recipes or grocery items were saved. The simulator was restored to dark appearance, standard Large text, All scope and List layout; Recipes still showed 13 recipes. Hardware VoiceOver, real Siri, speech recognition, background alarms and the other untested areas of the original review remain outside this fix verification.
