## Problem Statement

People discover recipes on Instagram, TikTok, and YouTube and want to bring them into Calendish through a shared or pasted link. A recipe may be written in the post caption or video description, or published on a recipe page linked from that text. Today, the link importer primarily reads structured recipe metadata from websites, so a social link can yield little useful cooking content even when a written recipe exists.

People should not have to copy captions, take screenshots, supply videos, or complete every missing field to make an import useful. They also need to see what was recovered before saving a recipe to their collection.

## Solution

Extend the existing link import flow to automatically recover written recipe content from public Instagram, TikTok, and YouTube links, including explicitly linked recipe pages. Prefer the linked recipe page when it contains recipe content; otherwise use the caption or description.

Prefill the existing New Recipe screen with the available fields. At least one recognizable ingredient or cooking instruction is enough to open that screen. Allow saving with a title and at least one ingredient OR instruction, without requiring the other section. Nothing becomes a saved recipe until the person sees the screen and explicitly taps Save.

Keep all acquisition and extraction processing on device. Preserve stated recipe facts without inventing missing information. Use the person's existing default serving count and zero preparation/cooking time when those values are unstated. If no useful recipe content can be recovered, show a simple error such as “Couldn’t get a recipe from this link.” Do not add missing-information flags or request additional input as a recovery step.

The first release processes written content only. Audio transcription, subtitle extraction, and video-frame reading are deferred. Platform coverage must be verified with native on-device acquisition; successful Mac probes do not establish reliable iPhone support or guarantee that every public social post is importable.

## User Stories

1. As a person discovering recipes, I want to share an Instagram recipe link to Calendish, so that I can bring its written recipe content into my collection.
2. As a person discovering recipes, I want to share a TikTok recipe link to Calendish, so that I can import available written ingredients and instructions.
3. As a person discovering recipes, I want to share a YouTube recipe link to Calendish, so that I can import recipe content from its description or linked recipe page.
4. As a person with a copied social link, I want to paste it into the existing link import form, so that I can use the same import flow without returning to the social app.
5. As a person using a social app's share sheet, I want Calendish to use recipe text provided alongside the link, so that useful shared content is not discarded.
6. As a person sharing a shortened social link, I want the importer to follow its destination when accessible, so that the share-link format does not prevent an otherwise usable import.
7. As a person importing a recipe, I want Calendish to read the available caption or description automatically, so that I do not have to copy it myself.
8. As a person importing a post that links to a recipe page, I want Calendish to try that page automatically, so that I can recover the fuller written recipe.
9. As a person importing conflicting written versions, I want the linked recipe page to take priority, so that my draft does not mix incompatible quantities or instructions.
10. As a person importing a post whose linked page cannot provide recipe content, I want Calendish to use the caption or description, so that available recipe information is still useful.
11. As a person importing a recipe, I want its stated ingredients and quantities preserved, so that the draft represents what the creator actually wrote.
12. As a person importing a recipe, I want its stated cooking instructions preserved in order, so that I can follow the creator's method.
13. As a person importing a recipe, I want its stated title, description, yield, servings, and times filled where recoverable, so that I avoid entering information already present in the source.
14. As a person importing an incomplete recipe, I want unstated quantities and instructions left unfilled, so that generated guesses do not appear as creator-provided facts.
15. As a person importing a recipe without a serving count, I want my existing default serving count used, so that imports behave consistently with the current app.
16. As a person importing a recipe without preparation or cooking times, I want the existing zero-time defaults retained, so that the importer does not invent durations.
17. As a person importing an ingredient-only recipe, I want its ingredients to prefill New Recipe, so that a missing method does not discard useful content.
18. As a person importing an instruction-only recipe, I want its instructions to prefill New Recipe, so that a missing ingredient list does not discard useful content.
19. As a person reviewing an imported recipe draft, I want the existing New Recipe screen, so that I can use familiar editing controls.
20. As a person reviewing an imported recipe draft, I want to change any recovered fields before saving, so that my saved recipe reflects my choices.
21. As a person reviewing an imported recipe draft, I want nothing added to my collection before I tap Save, so that an import never creates an unwanted saved recipe.
22. As a person reviewing an imported recipe draft, I want to cancel without creating a saved recipe, so that I remain in control of my collection.
23. As a person reviewing a partial recipe with a title and ingredients, I want to save without adding instructions, so that I am not forced to complete the source recipe.
24. As a person reviewing a partial recipe with a title and instructions, I want to save without adding ingredients, so that the recovered method can still be retained.
25. As a person reviewing an imported recipe draft, I want no missing-information flags, so that incomplete imports use the ordinary editor presentation.
26. As a person importing a post with several distinct recipes, I want the first identifiable recipe imported, so that I receive one coherent draft without an extra selection screen.
27. As a person importing a social recipe, I want its source link retained in the ordinary source field, so that I can return to the original post.
28. As a person importing a link with only a title, thumbnail, or hashtags, I want a simple failure, so that page metadata alone does not masquerade as an imported recipe.
29. As a person importing inaccessible, private, deleted, or unreadable content, I want a simple error if no recipe information is available, so that the failure is understandable.
30. As a person whose import fails, I want no request to paste text, attach screenshots, or supply a video, so that link importing remains automatic.
31. As a person importing a social recipe, I want extraction to stay on my device, so that Calendish does not rely on server AI or a retrieval proxy.
32. As a person importing when the on-device language model is unavailable, I want existing deterministic parsing used where it can recover recipe content, so that supported imports can still succeed without a cloud fallback.
33. As a person using existing website, text, image, or PDF imports, I want their established review-before-save flow preserved, so that adding social links does not disrupt existing import methods.

## Implementation Decisions

- Reuse the existing share extension, shared inbox, link import entry points, imported recipe draft, and New Recipe editor. Do not introduce a separate social import screen or automatic saved-recipe creation.
- The first implementation step is a bounded native acquisition check on the simulator and physical iPhone for public Instagram, TikTok, and YouTube links. Verify usable written text, redirected share links, and explicit recipe-page links before selecting shipping acquisition routes. Report platform-specific limitations rather than treating readable HTML or metadata as evidence of recipe extraction success.
- Keep platform-specific caption/description retrieval behind the existing link-import boundary. Internally separate acquiring source content from interpreting it, so platform changes do not require a new editor or persistence flow.
- Extend the shared import payload/inbox representation as needed to preserve a link and complementary text from the same share. Continue treating shared staging as pending input, not a saved recipe. Preserve existing image and PDF import entry points.
- Retain existing structured recipe extraction for recipe pages. Reuse the on-device text importer for written social content and usable linked-page text. No broad rewrite of unrelated website importing is required.
- Prefer an explicitly linked recipe page when it supplies at least one recognizable ingredient or instruction. If it is inaccessible or supplies no such content, try the caption/description. Do not silently combine conflicting recipe versions. A failure to read the linked page must not discard usable caption content.
- Read recipe-relevant written text; unrelated promotional, navigation, hashtag, and comment content must not generate a recipe. Do not assume a truncated preview is the complete caption.
- Recover the first identifiable recipe from multi-recipe content without merging separate dishes. Audio, subtitle, and visual video content do not participate in this release.
- Change the text importer's current requirement for both ingredients and steps so that either can produce an imported recipe draft. Validate recovered content against source text; ingredient-name overlap alone is insufficient evidence that generated quantities or instructions are faithful.
- Preserve source-provided quantities, units, instructions, and other recoverable recipe fields. Do not generate missing ingredients, quantities, methods, or durations. Existing preference/default values are editor defaults, not claims that those values appeared in the source.
- Prefill New Recipe, retaining the original social link in its ordinary source field. Keep the existing review, editing, loading, cancellation, and explicit-save interaction.
- Update shared editor validation to require a nonblank title and at least one nonblank ingredient OR instruction. Blank editor placeholders must not count as recipe content. Preserve the existing recipe ownership and sharing behavior when the person saves.
- A title, summary, thumbnail, or hashtags without an ingredient or instruction must not make a social import successful. If acquisition or parsing yields no useful recipe content, use the normal link failure presentation with a simple message. Do not direct the person to another input method.
- All acquisition and extraction processing stays on device. Direct network requests for existing published content are permitted; a server retrieval proxy, hosted extraction service, or cloud model fallback is not. Keep the existing deterministic parser where it can recover useful content when Foundation Models is unavailable.
- Choose acquisition routes consistent with their documented intended use. Instagram oEmbed is excluded because its official documentation restricts it to embedding and prohibits extraction for other purposes. TikTok oEmbed caption retrieval and YouTube description retrieval are candidates to validate, not preselected implementation contracts. No credentials or backend service have been provisioned for this feature.
- Use existing recipe persistence and ownership semantics; no new recipe storage model or database schema change is required by the agreed design.

## Testing Decisions

- Prefer one primary behavioral test boundary: imported content enters the existing import workflow and produces either an imported recipe draft for New Recipe or a simple failure. Exercise social acquisition, linked-page precedence, and partial parsing through that boundary rather than building independent tests for every internal helper.
- If deterministic testing requires a new seam, introduce only a narrow replaceable content-fetching dependency at the link-import boundary. Supply captured public-response fixtures or controlled responses there; avoid mocking platform parser internals or asserting implementation-specific regular expressions, selectors, or private helper calls.
- Good tests assert visible recipe content, faithful quantities and units, preserved instruction order, selected recipe/source, defaults, and failure behavior. They must detect invented content and cross-recipe mixing, not merely assert that all fields are populated.
- Cover a written recipe for each target platform; redirected share links; link-plus-text shares; successful linked recipes; unavailable or non-recipe linked pages with useful caption fallback; conflicting caption/page versions; ingredients-only and instructions-only recipes; several distinct recipes; and metadata-only content.
- Cover unavailable/private/deleted responses, malformed or truncated source text, absent model availability, parser rejection, and cancellation. Assert no cloud fallback, no manual-recovery request, and no missing-information flags. Model-dependent checks should assert source fidelity and valid outcomes rather than identical generated phrasing across model versions.
- Add a small set of UI/workflow checks for the same user flow: New Recipe contains recovered fields; the saved collection is unchanged before Save; cancelling does not create a recipe; and explicit Save accepts title-plus-ingredients or title-plus-instructions. Saving with no title or neither content section remains unavailable.
- Regression-check existing structured website, pasted text, image, and PDF review flows, including source values and defaults. Do not broaden the work into unrelated importer cleanup.
- Prior art is the repository's fixture-based recipe-link importer tests and its existing recipe-import test runner, which assert extracted values and optionally exercise a live URL. Follow the existing simulator UI/workflow testing conventions for presentation and persistence checks.
- Keep automated correctness tests deterministic. Treat live network acquisition checks as separate feasibility/integration evidence, recording platform, device, date, resolved URL, accessible text, and outcome. A single successful public example does not establish general platform reliability.
- On the physical iPhone, verify a full written recipe and a useful partial recipe where accessible, plus a link with no written recipe. Verify supported behavior when Foundation Models is available and the normal failure/fallback behavior when it is unavailable. If platform retrieval cannot be verified within the on-device boundary, report that limitation explicitly.
- After app code changes, run the repository-required simulator build/install/relaunch first, then the physical-iPhone build/install/relaunch. Keep the builds sequential. If the phone is disconnected, locked, or deployment fails, report that it was not updated and why.

## Out of Scope

- Downloading and transcribing video audio; extracting subtitle tracks; video-frame OCR or visual video understanding.
- Server AI, retrieval proxies, hosted social extraction services, and cloud fallbacks.
- Missing-information flags, confidence/provenance UI, conflict-selection screens, and generated recipe suggestions.
- Asking for pasted captions, screenshots, or supplied videos when a link import fails. Existing standalone text, image, and PDF import methods remain available as before.
- Automatic recipe saving, batch recipe creation, and a multi-recipe selection screen.
- Recipes that exist only in spoken narration, video-frame text, comments, or private content not available through the supported written-content routes.
- New social-account login flows, access bypasses, or a guarantee that every public social link can be imported.
- Duplicate-detection redesign, a new persistent import queue, and unrelated website-import or recipe-ownership redesigns.

## Further Notes

This spec synthesizes the accepted product decisions. Acquisition routes remain implementation work to verify on device; the research does not establish universal platform reliability.

Existing share extension and review-before-save behavior already provide the main user flow. The current text parser and editor both require ingredients and instructions; relaxing those requirements is necessary for the agreed partial import behavior. Existing saved recipe ownership/sharing rules remain authoritative. The on-device social import ADR records the deliberate trade-off of limited automatic coverage instead of a hybrid backend.

Competitor documentation supports the distinction between written-content import and broader video import. ReciMe documents caption-first extraction with an audio fallback; Sugo documents captions, subtitle/transcript routes, and linked-page precedence. Those broader video routes are deliberately deferred here. Competitor claims have not been independently benchmarked: [ReciMe import behavior](https://www.recime.app/help/en/articles/14773584-why-didn-t-my-recipe-import-correctly), [Sugo import behavior](https://sugo.kitchen/blog/every-way-to-import-a-recipe).

Bounded Mac probes found caption-like text on two TikTok samples, caption text on one Instagram recipe post, and a recipe description on one YouTube page. These samples did not establish recipe completeness or native-device reliability. YouTube's immediate subtitle fetch returned no content; no video/audio retrieval route was verified. Platform references for acquisition evaluation: [YouTube video descriptions](https://developers.google.com/youtube/v3/docs/videos/list), [TikTok video embeds](https://developers.tiktok.com/docs/en/embed-videos), [Instagram oEmbed restrictions](https://developers.facebook.com/docs/instagram-platform/oembed).
