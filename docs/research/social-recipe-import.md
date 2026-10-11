# Social recipe import: competitor behavior and feasibility

Research date: 2026-10-09. Status: research for a design interview. Sources below are first-party app documentation and platform documentation, except where an unresolved verification issue is explicitly identified. Marketing and help articles establish claimed behavior, not independently measured accuracy. No competitor accounts, paid plans, or live import corpus were tested.

## Accepted constraints from the design interview

The user wants faithful extraction of whatever recipe content can be recovered through a social link. Missing quantities or instructions must not be invented; missing-information flags are explicitly rejected. Successful imports open the normal recipe editor with the recovered content. If no useful recipe content can be recovered, show a simple error such as “Couldn’t get a recipe from this link.” Do not ask the person to paste a caption, attach screenshots, or supply a video as a recovery step.

All processing must happen on the device; a hybrid backend is rejected. Recommendations must fit those constraints: no server AI, retrieval proxy, or forced cloud fallback. Official platform APIs returning already-published metadata are a separate acquisition question from off-device AI processing. Local transcription/OCR is relevant only if the content can be obtained through the link, without asking for additional input.

A successful import requires at least one recognizable ingredient or cooking instruction. A title, thumbnail, or hashtags alone are insufficient. Prefill the existing New Recipe editor; no autosave. Explicit Save is allowed with a title plus at least one ingredient OR instruction. Preserve existing default servings and zero times when those facts are absent.

The first release reads written captions/descriptions and linked recipe pages. Audio transcription, subtitle extraction, and video-frame OCR are deferred. If a post contains several distinct recipes, prefill the first identifiable recipe rather than combining dishes or introducing a recipe-selection screen. An explicitly linked recipe page takes priority, with the caption/description used when that page cannot supply recipe content.

## Main finding

Caption extraction is a useful first tier, but several competitors already supplement it with narration or subtitle extraction. The acquisition problem is separate from parsing: a shared social URL does not give Calendish the caption, video bytes, or transcript. Platform APIs have different access boundaries. A stronger product could preserve incomplete imports, show the creator's evidence, and make repairs easy instead of silently producing a complete-looking recipe.

## What apps document

| App | Documented import behavior | Limits and unknowns |
| --- | --- | --- |
| ReciMe | Caption first; if insufficient, video audio; then an original recipe website. Share-sheet import and screenshots are documented. | Public content only; comments unsupported; one recipe at a time from a multi-recipe post. No disclosed video acquisition mechanism or independently measured success rate. |
| CookBook | Instagram and TikTok share sheet; caption extraction with a website-link fallback. Users can save without opening the app or open it to edit. | Help tips mention the caption or first comment, but do not describe comment acquisition. The reviewed guides do not establish transcription or visual understanding. |
| Pestle | Instagram Reels import; processing on the device; prompts for a missing name when ingredients and steps are recognized. | The 2024 first-party announcement initially supported English. This is historical evidence, not proof of current language coverage or current video/audio capability. |
| Sugo | TikTok caption then subtitle track; Instagram caption plus transcribed audio if needed; YouTube description and recipe links then transcript. Duplicate links reuse the saved recipe. | No Instagram comments/private accounts; TikTok photo slides are not read. Acquisition mechanics and accuracy have not been independently verified. |
| Paprika | Paprika 4 open beta announces Instagram, TikTok, Facebook and YouTube recipe importing. | September 28, 2026 beta announcement; extraction modalities and stable-release availability are not established by this source. |
| Recipe Keeper | Official site explicitly advertises importing from Instagram and TikTok, plus photo/PDF OCR. | No explanation of caption versus narration versus visual extraction in the reviewed source. |
| Samsung Food | Website URLs, share extension, recipe builder, and photo scanning. | Reviewed help explains compatible website metadata; it does not establish general Instagram/TikTok/YouTube video transcription. |
| Crouton | Website URL extraction and scanning recipes. | Reviewed first-party product/press pages do not establish current general social-video extraction. Absence from these pages is not proof the app cannot import a caption. |

Sources: [ReciMe import failures and extraction order](https://recime.app/help/en/articles/14773584-why-didn-t-my-recipe-import-correctly), [CookBook Instagram guide](https://help.cookbookmanager.com/en/article/how-to-import-recipes-from-instagram-1vj0rig/), [CookBook TikTok guide](https://help.cookbookmanager.com/en/article/how-to-import-recipes-from-tiktok-qo7w9f/), [Pestle announcement](https://pestlechef.app/blog/save-recipes-from-instagram), [Sugo import guide](https://sugo.kitchen/blog/every-way-to-import-a-recipe), [Paprika 4 beta announcement](https://www.paprikaapp.com/news/2026/09/28/paprika-4-is-now-in-open-beta/), [Recipe Keeper](https://recipekeeperonline.com/), [Samsung Food save guide](https://support.samsungfood.com/hc/en-us/articles/18756427379476-How-to-Save-Recipes-to-Your-Samsung-Food-Recipe-Box), [Crouton](https://crouton.app/), [Crouton press kit](https://crouton.app/press-kit.html).

### Important distinctions

ReciMe's audio fallback means a caption-only feature would have a narrower coverage promise. Its help identifies comments and multi-recipe posts as failure cases; screenshots are a practical recovery route. [ReciMe](https://recime.app/help/en/articles/14773584-why-didn-t-my-recipe-import-correctly)

Sugo documents leaving unstated quantities blank but drafting short steps when only ingredients are supplied. That is a meaningful distinction between extracting creator instructions and generating plausible instructions. Its guide also describes a transcript ingredient-validation failure and its correction. These are self-reported behaviors, not validation results for Calendish. [Sugo](https://sugo.kitchen/blog/every-way-to-import-a-recipe)

Our Meals documents a share-sheet enqueue flow, background processing, a progress tile, and combined YouTube description/narration extraction. It says imports usually take roughly 30 seconds and failed imports do not consume a free recipe. This illustrates a separate interaction pattern from waiting for extraction in the share extension. [Our Meals YouTube guide](https://ourmeals.io/help/import-from-youtube/)

Recipe Bro's general import FAQ says social importing extracts captions/descriptions and retains the video link; its YouTube-specific page additionally claims pinned comments and video analysis. Treat this inconsistency as unresolved rather than evidence of a known multimodal architecture. [General import FAQ](https://recipebro.com/import), [YouTube page](https://recipebro.com/import-recipes/youtube)

## Platform access: what is actually available

### YouTube

`videos.list` with `part=snippet` returns title, channel ID, description and other metadata for supplied IDs. A request costs one quota unit. This is a documented path to public descriptions rather than guessing from a truncated page preview. [YouTube videos.list](https://developers.google.com/youtube/v3/docs/videos/list)

`captions.download` requires authorization and permission to edit the video; it costs 200 quota units. Consequently, signing a viewer into Google does not grant general transcript download access for arbitrary cooking videos. A public description import and an arbitrary-video transcript import need distinct feasibility plans. Competitors' claimed transcript support does not identify an official API route. [YouTube captions.download](https://developers.google.com/youtube/v3/docs/captions/download)

### TikTok

TikTok's official public oEmbed example returns caption-like text in `title`, creator details, thumbnail and embed HTML for a video URL. The documented response does not provide a video download or transcript. It is a promising caption acquisition experiment, not proof of full caption coverage or permission for every proposed persistent use. Validate short-link resolution, long captions, deleted posts and intended reuse before committing. [TikTok Embed Videos](https://developers.tiktok.com/docs/en/embed-videos)

The Display API is creator-authorized. `video/query` checks that requested IDs belong to the authorized user, even though `video_description` is an available field. Authorizing the person saving recipes would not expose arbitrary creators' videos through this route. [TikTok Query Videos](https://developers.tiktok.com/docs/en/tiktok-api-v2-video-query), [Display API overview](https://developers.tiktok.com/docs/en/display-api-overview)

Research API access is not a commercial importer escape hatch: TikTok's FAQ explicitly excludes creators, advertisers and commercial users from Research Tools eligibility. [TikTok Research API FAQ](https://developers.tiktok.com/docs/en/research-api-faq)

### Instagram

Meta's own Postman workspace documents APIs for professional accounts; the Facebook Login API cannot access ordinary consumer accounts. Its messaging documentation says a shared-media webhook contains only the media URL. This supports treating a social share as an acquisition pointer rather than assuming the caption travels with it. These messaging details are not a measurement of the iOS share-sheet payload. [Meta Instagram API workspace](https://www.postman.com/meta/workspace/instagram/documentation/23987686-9386f468-7714-490f-9bfc-9442db5c8f00)

Initial web-tool retrieval of the current [Instagram platform docs](https://developers.facebook.com/docs/instagram-platform/) and [Instagram oEmbed docs](https://developers.facebook.com/docs/instagram-platform/oembed) failed with HTTP 429 or inaccessible-page errors. A subsequent direct no-login `curl` GET to the latter official URL succeeded with HTTP 200 and a Markdown document. It explicitly limits oEmbed to displaying embedded content and prohibits extraction/persistence or derivation for other purposes. Instagram oEmbed should therefore not be selected as a recipe extraction route. Direct post-page access is a different mechanism, whose permitted use and reliability still need verification.

### Foundation Models

The existing Calendish importer uses `SystemLanguageModel.default` with a text prompt; the reviewed Apple documentation does not give it automatic access to social content. Apple's documented on-device language session budget is 4,096 tokens including instructions, schemas, input and output. Long narration needs selection/chunking, and OCR or speech recognition can produce text for the existing importer. This observation does not assert that every newer Foundation Models capability is text-only. Platform acquisition and model extraction are different seams. [Apple Foundation Models tasks](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models), [context management](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)

Apple documents on-device file transcription using SpeechTranscriber, with device and locale requirements, and Vision text recognition for images/video frames. These establish building blocks for processing a user-provided video locally; they do not establish faithful recipe extraction accuracy or the ability to retrieve a third-party platform's video from a link. [WWDC25 SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/), [Vision](https://developer.apple.com/documentation/vision)

## Calendish baseline

These are local source observations, not proposed changes:

- [ShareViewController.swift](../../ShareExtension/ShareViewController.swift) saves a shared attachment to the inbox and closes; parsing happens when Calendish opens.
- [RecipeImport.swift](../../Shared/RecipeImport.swift) represents one link, text, images or PDF. Combining attachments prefers PDF, then images, then link, then text. Complementary caption text can be discarded when a link is also present.
- [RecipeLinkImporter.swift](../../calendish/Features/Recipes/Import/RecipeLinkImporter.swift) fetches HTML and extracts schema.org Recipe JSON-LD plus page metadata. It does not acquire social transcripts or pass social captions to the text importer. `ImportedRecipe` holds a recipe and optional photo, without extraction evidence or uncertainty.
- [RecipeTextImporter.swift](../../calendish/Features/Recipes/Import/RecipeTextImporter.swift) uses Foundation Models with a heading parser fallback. It requires ingredients and steps. Its ingredient grounding test checks word overlap for at least half of ingredients, not fidelity of all quantities or instructions.
- [RecipeImageImporter.swift](../../calendish/Features/Recipes/Import/RecipeImageImporter.swift) already supplies an OCR route for screenshots. This can recover captions/comments the URL importer cannot read.
- [ContentView.swift](../../calendish/App/ContentView.swift) removes the shared inbox item when the import view appears, before a successful recipe save. The editor requires a title, ingredient and step; an editor draft may persist once reached, but the original inbox source is removed earlier. This is a retry-source preservation concern, not evidence that all editor drafts are lost.

ADR 0003's on-device/no-audio-retention decision concerns hands-free cook mode. It does not decide whether a future importer may process a public social video's audio remotely. [ADR 0003](../adr/0003-on-device-cook-mode-recognition.md)

## Earlier opportunities evaluated during the interview

The following preserves the research hypotheses. The accepted constraints above take precedence: missing-information flags and manual recovery requests were rejected. Source evidence, durable retry, and other ideas below are not accepted requirements.

1. **Evidence-backed review.** Preserve creator/source links and distinguish caption, website, transcript and screenshot evidence. Expose conflicting quantities and missing times rather than making a complete-looking draft. Field-level evidence is a hypothesis for differentiation; the reviewed competitor docs do not prove nobody offers it.
2. **Save incomplete work.** Keep a shared link and available fragments as a durable import draft when access fails or instructions are absent. Let users attach screenshots, pasted captions or creator comments to the same draft. This fits the existing inbox better than dropping an unsuccessful import.
3. **Prefer creator-authored recipes.** Try sufficient caption/description text and explicit recipe website links before expensive local narration processing. A recipe page may provide more complete source quantities than speech. Preserve the social source as well as the linked recipe source. When a link does not expose usable content, ask for shared text/screenshots or an available user-provided video rather than silently using a backend.
4. **Separate extraction from reconstruction.** If generated steps are offered, label them as suggestions and require an explicit product decision about whether they belong in saved recipes. Never present inferred quantities as stated by the creator.
5. **Handle multiple recipes and contradictions.** A meal-prep post can contain several dishes; a caption can correct an on-screen amount. Ask which dish to import or which source to trust instead of merging silently. This adds interaction cost; assess how often it is needed.
6. **Repair without starting over.** Provide an actionable state such as “Could not read this post” or “Ingredients found; steps missing,” retaining the original URL and partial result. Duplicate detection and retry should not create duplicate recipes.

## Proposed evaluation before committing to an architecture

Use creator posts supplied by the user and permitted test fixtures. Benchmark independently for each platform and modality, and compare the same links in competitor apps if access is available. Include full captions, description-only recipes, explicit external recipe links, spoken-only recipes, music-only videos with on-screen text, carousel slides, recipes in creator comments, multiple dishes, missing quantities, conflicting caption/narration/on-screen values, short links, private/deleted/region-blocked content, and unsupported languages. Test devices without available Apple Intelligence separately.

Measure acquisition success separately from parse success; complete recipe coverage; exact quantity/unit fidelity; retained optional ingredients, substitutions and notes; invented facts; user correction time; latency, energy use and model/device availability; recovery after closing the share sheet/app; duplicate handling. A fast importer with fabricated quantities should fail the fidelity criterion even when every field is populated.

The design was synthesized and published at the user’s request as [GitHub issue #3](https://github.com/OwenVey/calendish-ios/issues/3). Source precedence is accepted: prefer the linked recipe page, falling back to the caption/description. First-release written-content scope and first-recipe behavior are accepted. Remote processing, missing-information flags, invented recipe content, and manual recovery requests are rejected. Partial saves through the existing editor and existing default servings/zero times are accepted. Audio transcription, subtitle extraction, and video-frame OCR are deferred. Unresolved technical work includes native acquisition verification for the target platforms, live share payload inspection, Instagram acquisition/policy verification, and a real extraction corpus. Competitor popularity is not established by this research; feature availability alone does not demonstrate a universal “must-have.”

## Bounded acquisition feasibility follow-up

Date: 2026-10-09. These observations came from terminal HTTPS requests on the development Mac, without credentials, cookies or login. They are host observations, **not iPhone verification**. Methods: `curl -L --max-time 20` and Python standard-library `urllib.request`; Python public-page requests supplied `User-Agent: Mozilla/5.0`, capped page bodies at 2 MB, and used 15–20 second timeouts. No video/audio was downloaded, no package was installed, and no app code changed. One accessible example establishes a candidate, not platform-wide reliability.

| Platform | Caption/description observation | Subtitles/audio observation | First-release feasibility |
| --- | --- | --- | --- |
| YouTube | Official `videos.list(part=snippet)` documented; not live-tested without an API credential. A public recipe watch page exposed a 261-character `shortDescription`. | Page exposed one caption-track URL, but its immediate fetch returned HTTP 200 with **zero bytes**. No audio route verified. | **Candidate:** official description API. Direct page extraction is an undocumented prototype alternative. **No verified general transcript/audio route.** |
| TikTok | Official oEmbed returned HTTP 200 and caption-like `title` for the documented sample and one recipe link. Recipe title was 293 characters. | Recipe-page hydration contained a playback address but zero subtitle entries. No playback/audio request made. | **Candidate:** oEmbed captions, subject to intended-use review. **Needs prototype:** direct page parsing. **No verified general subtitle/audio route.** |
| Instagram | Public reel and captioned embed page returned HTTP 200. Reel metadata exposed creator text; embed caption had 176 characters describing the dish, no ingredient heading or detected quantity/unit. | No transcript/audio route tested or verified. | **Needs prototype:** direct public post-page caption acquisition. **No confirmed supported general API for arbitrary saved posts.** oEmbed excluded by its embedding-only restriction. |

Exact public probes:

- TikTok official sample: `https://www.tiktok.com/oembed?url=https%3A%2F%2Fwww.tiktok.com%2F%40scout2015%2Fvideo%2F6718335390845095173` returned JSON caption-like title/creator/thumbnail/embed HTML. [Official sample](https://developers.tiktok.com/docs/en/embed-videos)
- TikTok recipe: `https://www.tiktok.com/@alya.cookss/video/7666457673751072033` and `https://www.tiktok.com/oembed?url=https%3A%2F%2Fwww.tiktok.com%2F%40alya.cookss%2Fvideo%2F7666457673751072033` returned a hydration item and caption-like title. A quantity/unit regex did not match the title; whether its wording supports faithful ingredients or steps is untested. A `subtitleInfos` marker elsewhere in HTML did not mean this video had subtitle tracks.
- Instagram recipe: `https://www.instagram.com/reel/CqwZ49IpAlI/` and `https://www.instagram.com/reel/CqwZ49IpAlI/embed/captioned/` exposed caption text for this post. [Creator page linking to reel](https://nutterie.com/blogs/news/pistachio-mint-basil-pesto-by-chef-ricardo-lo-schiavo)
- YouTube recipe: `https://www.youtube.com/watch?v=BJVFg2AXCtw` exposed `shortDescription` with ingredient text. `https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DBJVFg2AXCtw&format=json` returned title/creator/embed metadata, **no description**. Immediately fetching `captionTracks[0].baseUrl` returned zero bytes. The signed URL is not recorded as a stable interface; expiration, client/IP restrictions and access conditions were not diagnosed.
- Meta documentation: `https://developers.facebook.com/docs/instagram-platform/oembed` returned HTTP 200, 4,752 bytes of Markdown, with the embedding-only/extraction restriction. [Official source](https://developers.facebook.com/docs/instagram-platform/oembed)

The smallest useful next experiment is an isolated native `URLSession` acquisition probe on the simulator and physical iPhone using these links plus one caption with complete quantities and one spoken-only post per platform. Record HTTP outcome, resolved URL, exact available text, recipe-site links and whether an existing subtitle track actually returns nonempty text. Keep acquisition separate from Foundation Models parsing. Check that a retrieved ingredient OR instruction can reach the editor without generating missing facts; current both-required parsing would hide partial acquisition success.

Test YouTube's official description request with a configured restricted API key if that candidate is pursued; no retrieval proxy is needed for the documented request. Verify intended use of responses before selecting a shipping route. Do not pursue Instagram oEmbed extraction or treat a playback URL/empty transcript as proven video support. Existing `LocalHandsFreeSpeech.swift` uses local SpeechAnalyzer/SpeechTranscriber, reducing integration uncertainty **after audio is available**, but does not solve URL-to-audio acquisition. With manual and server fallbacks rejected, inaccessible link-only content must produce a truthful simple error. These probes do not support promising automatic importing from every public video.

## Published specification

The accepted design was published using to-spec as [GitHub issue #3](https://github.com/OwenVey/calendish-ios/issues/3), labelled ready-for-agent. The full local specification is [Social recipe import](../social-recipe-import.md). No app implementation was made during this research/design session.

## Implementation acquisition check

Date: 2026-10-09. Routes shipped in [SocialPost.swift](../../calendish/Features/Recipes/Import/SocialPost.swift); all requests go directly from the device to the platform, without credentials, a proxy, or server processing.

| Platform | Route | Mac `URLSession` live import (real importer code) |
| --- | --- | --- |
| YouTube | Watch page `shortDescription`; `og:title` for the title. `youtu.be` redirected to `m.youtube.com/watch?v=…`. | `youtu.be/BJVFg2AXCtw`: 11 ingredients, 0 steps, 2 servings, photo, with and without the model. |
| Instagram | Public `/p/CODE/embed/captioned/` page caption (not the oEmbed API). Share links resolve by redirect. The post page's `og:description` is a preview and is not used. | `instagram.com/p/DePh8DLupVq`: 10 ingredients, 7 steps, photo. `reel/CqwZ49IpAlI` (caption without a recipe): “Couldn’t get a recipe from this link.” |
| TikTok | Video page hydration `desc` for the video's ID (its key path differs by user agent), then official oEmbed `title`. `vm.tiktok.com` short links resolve by redirect. | `@alya.cookss/video/7666457673751072033` (unlabelled bullet list, no quantities): fails without the model; with it, 8 ingredients without invented quantities, 0 steps. |

These are host results using the shipping Swift code, not iPhone results. The build was installed on Owen’s iPhone, but no on-device import of these links was observed during implementation. Instagram's embed page and TikTok's page data are undocumented and can change; their failure produces the normal link error.
