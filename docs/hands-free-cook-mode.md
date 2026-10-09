# Hands-free cook mode

Design interview complete. All decisions below were accepted during the interview. At the product owner's request, the synthesized implementation spec was published as [GitHub issue #2](https://github.com/OwenVey/calendish-ios/issues/2), labeled `ready-for-agent`. Implementation and physical-device acceptance have not started.

## Confirmed decisions

- The first release supports “next”, “back”, and “start timer” for recipe-step navigation and cooking timers.
- Listening operates only while Cook Mode is visible. Leaving Cook Mode, switching apps, or locking the phone stops listening.
- Keep the screen awake during hands-free use and show listening status clearly.
- The cook explicitly enables voice commands once, then speaks commands directly without a wake phrase or additional tap. Provide a visible stop-listening control.
- “Start timer” starts the timer offered on the current step, using the existing duration extraction: first recognized duration, shorter end of a range. If no duration exists, say “No timer on this step”. If that step already has a running timer, report it without restarting or duplicating it.
- “Back” on the first step and “next” on the last step stay put and announce the boundary. Finishing remains an explicit tap.
- Match short, standalone commands, including “next step”, “go back”, and “start the timer”. Ignore commands embedded in longer conversation.
- Give brief spoken feedback alongside visible results, such as “Step 3” or “Five-minute timer started”. Do not automatically read the instruction.
- After backgrounding, locking, or an audio interruption, preserve the step and running timers but require explicit re-enabling. Show “Voice commands paused”.
- While hands-free listening is enabled, keep the screen awake regardless of the existing preference. Restore normal preference behavior when listening stops.
- Recognition stays on-device. Do not save audio or transcripts or fall back to server recognition. If local recognition is unavailable, explain why and retain touch controls.
- Recognize English commands only in the first release. No explicit English-only label is needed: the app is intended to be downloadable only by English users, per the product owner.
- While hands-free listening is active, replace the blocking in-app timer-completion alert with a nonblocking banner and brief spoken announcement. Existing system alarms and notifications remain in effect outside the app.
- Allow other audio to continue; briefly lower its volume for spoken feedback where iOS permits.
- Execute each completed command utterance once, accepting a brief recognition delay. Ignore microphone input during the app's own spoken feedback, then resume listening automatically; this is distinct from external audio interruptions, which require explicit re-enabling.
- Accept that another person or a TV speaking a standalone command may trigger it. Explain this limitation during activation and provide an obvious stop-listening control. Speaker identification is outside the first-release scope.
- Request microphone access only on first activation. Briefly explain the need, and offer a Settings link if denied. Cook Mode remains usable without voice.
- If a required model is missing, enabling voice commands starts preparation/download with “Preparing voice commands”, progress, and a cancel control. Begin listening when ready only if the cook is still in the same active Cook Mode and has not cancelled. Failed preparation offers Retry and retains touch controls.
- Unexpected recognition failure visibly pauses listening and requires a tap to retry. Never show “Listening” when capture has failed. Ignore unrecognized speech quietly.
- Keep listening while the ingredient panel is open. Touch navigation and voice commands operate on the same current step. Leaving Cook Mode stops listening.

## Acceptance check

Readiness requires physical-iPhone testing at normal speaking volume from roughly 1–2 metres away, with a kitchen fan and music running. Record failures before calling the feature ready.

- Verify all three commands and accepted aliases.
- Verify no duplicate actions for a single utterance and no actions for commands embedded in conversational phrases.
- Verify navigation boundaries, timer start, missing timer duration, and an already-running timer.
- Verify audible feedback and nonblocking in-app timer completion.
- Verify interruption recovery, explicit re-enabling, and accurate listening status.
- Verify ingredient-panel use and touch navigation alongside voice.
- Verify permission denial, model preparation cancellation/failure, recognition failure, and restoration of the screen-awake preference.

## Verified platform constraints

- The app's deployment target is iOS 26.0. Apple's SpeechAnalyzer APIs are therefore available without changing the minimum OS.
- Apple's newer speech transcription models process audio on-device but require supported hardware, a supported locale, and installed model assets. Initial model preparation may require a download.
- Source: [Apple's SpeechAnalyzer overview](https://developer.apple.com/videos/play/wwdc2025/277/).

## Existing behavior

- Cook Mode currently respects a keep-screen-awake preference; hands-free listening overrides it as described above.
- A step’s timer uses the first recognized duration in its text; ranges use the shorter duration.
- The final step has a Finish button, which ends Cook Mode and marks the recipe as cooked when applicable.
- Timers persist independently of Cook Mode and can finish while the app is in the background.
