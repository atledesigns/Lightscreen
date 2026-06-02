# PRD — Lightscreen (Personal Mac Screenshot App)

> **Status:** Draft v2, updated 2026-06-02. V1 surfaces and identity locked (name, sparkle, vibe count, window-selection UX). Produced via `/grill-me` → `/to-prd`.
> **Source of design context:** `/Users/atle/.claude/projects/-Users-atle-Documents-Claude/memory/project_screenshot_app.md` (+ sibling `user_role.md`).
> **Issue tracker:** None configured. `ready-for-agent` label not applied (no tracker exists).
> **Codebase:** Does not exist yet. PRD precedes any code.

---

## Problem Statement

Atle is a designer who takes screenshots constantly — for messaging, but increasingly for sharing on social media, building mood boards, and documenting his design career publicly. macOS's native screenshot tool produces raw, unstyled images that pile up on the Desktop as `Screenshot 2026-…` files. To make any captured image presentable enough to post, Atle currently opens **Figma** and manually adds a gradient background, padding, drop shadow, and a chosen aspect ratio — every single time. This Figma round-trip is slow, breaks flow, and is wildly disproportionate to the task.

The pain has four concrete dimensions:

1. **Beautification friction.** Every shareable screenshot requires opening Figma to dress it up — adding a gradient (with colors usually sampled from the image itself), padding the image to ~80% of the frame, applying a soft drop shadow, sometimes rounding the corners, and resizing to the platform's aspect ratio (1200×675 for Twitter, 1080×1080 for Instagram).
2. **No full-length webpage capture.** Long pages must be screenshotted in sections and manually stitched.
3. **Desktop clutter.** Captures auto-save to the Desktop and bury themselves in date-stamped filenames.
4. **No clean window capture.** Window screenshots include real window chrome (tabs, bookmarks, plugin icons, personal title-bar text) that's inappropriate for public posts and requires manual cleanup.

Existing paid tools (Shottr, CleanShot X, Xnapper) solve some of these, but all push cloud uploads, accounts, or telemetry — incompatible with Atle's privacy-first, fully-local, "own my tools" stance.

## Solution

A privacy-first, fully-local macOS app, native to macOS Tahoe 26, that captures screenshots and **either keeps them raw (for collecting/reference) or routes them through a built-in beautify editor (for sharing).** The beautify editor automates and consolidates everything Atle currently does in Figma — auto-sampling gradient colors from the image, applying padding/shadow/corners with sensible defaults, offering preset "vibes," supporting device mockups (Mac window / iPhone / Browser chrome) with privacy-safe generic replacements, and producing output in the right aspect ratio for the destination platform. The app lives in the menu bar (no dock icon clutter), is triggered by a single global hotkey, and stores captures in a persistent library that Atle can review every 60 days. Nothing leaves the Mac, ever.

The app does NOT compete with macOS's native `⌘⇧4` for quick "send a screenshot to a friend in iMessage" use cases — Atle keeps that workflow. This app is purpose-built for the "screenshot → shareable artifact" pipeline.

## User Stories

### Triggering captures

1. As a designer, I want to press a single global hotkey (`⌘⇧7`) to open the capture picker, so that I don't have to remember multiple shortcuts.
2. As a designer, I want the picker to extend Apple's `⌘⇧3/4/5/6` family numerically, so that it slots into my existing screenshot muscle memory.
3. As a designer, I want the picker to show three capture types — Region, Window, Full Page — so that I can pick the shape of capture I need.
4. As a designer, I want the picker to have a sticky Raw ↔ Beautified toggle, so that during a mood-board collecting session I don't have to re-toggle for every capture.
5. As a designer, I want Beautified mode to be the on-launch default, so that the most common flow (sharing) requires no setup.
6. As a designer, I want clicking a capture-type button in the picker to immediately start that capture (no extra confirmation), so that there's no friction between intention and capture.

### Region capture

7. As a designer, I want to drag a box around any region of any screen, so that I can capture exactly the part I want.
8. As a designer, I want the drag affordance to match Apple's native behavior, so that it's familiar.

### Window capture

9. As a designer, I want to hover over any visible window and see it highlighted, so that I can confidently pick the right one before clicking.
10. As a designer, I want to click a highlighted window to capture it, so that the interaction is one gesture.
11. As a designer, I want to capture windows that are partially hidden behind others, so that I don't have to rearrange my desktop before capturing.
12. As a designer, I want the captured window's real chrome (title bar text, traffic lights, plugin icons, tabs, bookmarks) replaced with a generic, presentation-ready chrome by default, so that I never accidentally expose personal information in a public post.
13. As a designer, I want a one-click toggle to keep the original chrome when I want authenticity, so that I have the option for specific shots.
14. As a designer, I want windows without standard chrome (popovers, Spotlight, system menus) placed directly on the background without fake chrome, so that the output isn't visually wrong.

### Scrolling / full-page capture

15. As a designer, I want auto-scroll to be the default for full-page captures, so that a single click captures a whole webpage end-to-end.
16. As a designer, I want a "Retry manually" rescue button shown immediately after auto-scroll finishes, so that I can recover from stitching failures (duplicate sticky headers, missed sections) without re-doing the whole capture.
17. As a designer, I want very tall captures (e.g., 1200×8000px scrolling shots) to automatically open the editor with aspect ratio set to "Original," so that they don't get squished into a 16:9 frame by default.

### Floating preview (post-capture)

18. As a designer, I want a floating preview to appear in the bottom-right of the screen after capture, so that the location matches Apple's familiar pattern.
19. As a designer, I want the floating preview to linger for 5 seconds and then disappear, so that it doesn't block my work.
20. As a designer, I want to drag the floating preview into another app or Finder window, so that I can drop the capture directly where I want it without going through a save dialog.
21. As a designer, I want to click the floating preview to open the editor (Beautified mode) or the save popover (Raw mode), so that one click takes me to the next step.
22. As a designer, I want ignoring the floating preview to auto-save the capture to the library, so that nothing is ever lost by inaction.

### Beautify editor

23. As a designer, I want the editor to open immediately for Beautified captures, with a sensible default styling already applied, so that I can iterate from a starting point rather than a blank canvas.
24. As a designer, I want the editor's preview to update live as I adjust controls (no Apply button), so that iteration is fast.
25. As a designer, I want a vibe picker strip across the top of the editor showing preset styles rendered against my actual screenshot, so that I can compare looks at a glance and pick by feel rather than by label.
26. As a designer, I want to save my own custom vibes via a `[+]` button, so that my favorite combinations are one click away.
27. As a designer, I want the background to default to a 2-color gradient auto-sampled from the dominant colors of my screenshot, so that the gradient already feels coherent with the image without manual color picking.
28. As a designer, I want to manually override the gradient colors and angle, so that I can refine when the auto-sample isn't perfect.
29. As a designer, I want to choose solid color or transparent backgrounds as alternatives to gradient, so that I have options when the gradient isn't what I want.
30. As a designer, I want a padding slider (default 10% per side ≈ 80% scale), so that I can adjust the space between my screenshot and the frame edge.
31. As a designer, I want a shadow control with on/off + intensity (default: soft, ~40px blur, slight downward offset, low opacity), so that the screenshot feels lifted from the background.
32. As a designer, I want a rounded-corners slider (default 12px, range 0–32px), so that I can apply the corner radius I prefer.
33. As a designer, I want device-frame options — None, Mac window, iPhone, Browser — so that my screenshots can be presented inside generic device chrome for portfolio-style posts.
34. As a designer, I want the Browser frame to include a faux URL bar I can edit, so that my screenshots can read as "this is on atle.design" without leaking my actual current URL.
35. As a designer, I want an aspect ratio dropdown with 16:9 (Twitter — default on first launch), 1:1 (Instagram square), 4:5 (Instagram portrait), 9:16 (Stories/Reels), 3:2 (Dribbble), 1.91:1 (LinkedIn/OG), Original, and Custom, so that I can match the destination platform.
36. As a designer, I want the last-used aspect ratio to be sticky for the next capture, so that consecutive captures in a session don't need re-picking.
37. As a designer, I want an inline editable name field in the editor's top bar, so that I can rename the capture during the editing session rather than only at save time.
38. As a designer, when a capture is taller than the current aspect ratio, I want a "Split into…" button (2 / 3 / 4 / Custom panels) that previews cut lines I can drag to adjust, so that I can produce carousel-ready output.
39. As a designer, I want split outputs saved as `name_01.png`, `name_02.png`, etc., to the same chosen destination, so that they're easy to upload as a sequence.

### Saving & destinations

40. As a designer, I want every save to flow through a popover modeled on macOS Preview's save UI (Name field, Tags field, "Where" dropdown), so that the interaction is familiar.
41. As a designer, I want the default "Where" to be the app's library, so that captures don't pile up on the Desktop and inaction is safe.
42. As a designer, I want to override "Where" to any folder on disk, so that captures can be routed directly into specific project folders.
43. As a designer, I want the "Where" dropdown to surface recent destination folders, so that frequent destinations are one click away.
44. As a designer, I want the app to auto-learn frequent destinations and let me pin favorites in settings, so that the picker stays clean and personalised.

### Library

45. As a designer, I want the library accessible via "Show Library" in the menu bar dropdown, so that it's always discoverable.
46. As a designer, I want the library window to show captures as a grid of thumbnails, so that I can scan visually.
47. As a designer, I want thumbnails grouped by date (Today / Yesterday / Earlier this week / Last week / Earlier), so that "the one from yesterday" is findable without thinking.
48. As a designer, I want thumbnail labels to use Apple's default naming format (`Screenshot 2026-06-02 at 14.32.18`), so that the convention is familiar.
49. As a designer, I want hovering a thumbnail to show a larger preview and quick action buttons (Open in editor, Reveal in Finder, Move to…, Delete), so that common actions don't require right-clicking.
50. As a designer, I want to double-click a thumbnail to open it in the editor (works for both raw and beautified — raw opens with no styling applied), so that I can beautify any past capture retroactively.
51. As a designer, I want to drag a thumbnail out of the library into any Finder folder or app, so that pulling captures into projects later is fast.
52. As a designer, I want a search bar that filters by filename, so that I can find specific captures.
53. As a designer, I want a bottom status bar showing capture count and total storage size, so that I'm aware of the library's footprint.
54. As a designer, I want the library to never auto-purge, so that nothing is ever lost without my consent.
55. As a designer, I want a prompt every 60 days asking if I want to review old captures, so that I have a regular nudge to clean up without losing control.

### Identity & feel

56. As a designer, I want a single global hotkey (`⌘⇧7`) and nothing else to remember, so that the app stays low-friction.
57. As a designer, I want the app to live only in the menu bar (no dock icon), so that it stays out of the way until I summon it.
58. As a designer, I want the visual identity to embrace macOS Tahoe 26's Liquid Glass language, so that the app feels native to my current OS.
59. As a designer, I want the visual identity to feel playful and warm (Pokémon-coded), so that the app I use daily for years has personality.
60. As a designer, I want subtle particle/shimmer moments on capture and save, so that completing an action feels satisfying without being noisy.
61. As a designer, I want optional sound feedback (off by default), so that I can opt in if I like it.
62. As a designer, I want voiced empty states ("No catches yet — press ⌘⇧7 to start.") instead of clinical placeholder text, so that the app feels alive.
63. As a designer, I want a name and visual identity that references Pokémon thematically (final name TBD; candidates: Sketch, Smeargle, Aurora), so that the app's character matches my personal taste.

### Privacy & ownership

64. As a designer, I want the entire app to run on-device with zero network calls in v1, so that no capture data ever leaves my Mac.
65. As a designer, I want no account, sign-in, telemetry, or cloud upload features in v1, so that the app is mine alone.
66. As a designer, I want all on-disk storage (library, settings, thumbnails) inside my user account's standard app directories, so that I always know where my data lives.
67. As a designer, I want browser/window chrome replaced by default in device frames, so that personal info (tabs, bookmarks, document titles) never escapes accidentally.

### Library multi-select & cleanup

68. As a designer, I want a voiced empty-state line in the library ("Morning. No catches yet — try ⌘⇧7.") that adapts to time of day, so that an empty library feels alive rather than clinical.
69. As a designer, I want to cmd-click and shift-click thumbnails to multi-select, so that I can act on many catches at once.
70. As a designer, I want selected thumbs to show a small checkmark in the top-left + a system-accent border, so that the selection is unambiguous at a glance.
71. As a designer, I want a floating action bar to slide up from the bottom of the library window when 1+ items are selected — showing selection count on the left, "Move to…" and "Delete" in the middle, and "Deselect all" on the right — so that bulk actions are reachable without right-clicking.
72. As a designer, I want bulk delete to confirm with a small sheet ("Delete 3 catches?") in destructive button styling, so that I don't accidentally lose multiple items, while single-item delete from hover quick-actions stays no-confirmation since it's reversible same-session.
73. As a designer, I want "Move to…" in the bulk bar to use the same dropdown shape as the save popover's Where field, so the mental model is consistent across the app.
74. As a designer, I want the 60-day review prompt to appear both as a macOS system notification AND as a banner across the top of the library window — with voiced copy ("You have a lot of catches. Want to release some?") that taps into multi-select pre-loaded for batch delete — so that cleanup is one motion not many. Dismiss = next prompt in 60 days.

## Implementation Decisions

### Architecture

- **Native macOS app**, single binary, built with **Swift + SwiftUI** (with **AppKit** interop where required — menu bar item, global hotkey listener, screen overlays for region/window capture).
- **Minimum macOS Tahoe 26.** No backporting. Uses **ScreenCaptureKit** for all capture (no legacy CGWindowList fallback).
- **Lives in the menu bar only.** `LSUIElement = true` (the technical setting that says "no dock icon"). The menu bar item is the only persistent surface.
- **Fully on-device.** No HTTP/network code in v1. Foundation Models (Apple's on-device LLM in Tahoe 26) explicitly NOT used in v1 — naming, search, redaction all remain manual.
- **Bundle identifier and app name** TBD pending naming decision.

### Modules (deep, prioritized for testability)

- **Capture Engine** — wraps ScreenCaptureKit. Accepts a `CaptureRequest` (mode: region/window/scrolling, target identifier, options). Returns image data (or a stream of frames for scrolling). Hides all ScreenCaptureKit complexity behind a small interface. Integration-tested only.
- **Auto-Scroll Driver** — drives scroll in target windows via macOS Accessibility APIs and/or `CGEventCreateScrollWheelEvent`. Returns success/failure + ordered frames. Integration-tested only.
- **Image Stitcher** — pure function. Takes ordered overlapping frames, returns a single tall image. Detects and dedupes repeating sticky headers/footers. Unit-tested with fixture image sequences.
- **Color Sampler** — pure function. Takes an image, returns the top-N dominant colors weighted by area, with simple harmony rules (skip near-duplicates, prefer saturated). Unit-tested with fixture images.
- **Beautify Renderer** — pure function. Takes `(image, BeautifyStyle)` and produces the rendered output. `BeautifyStyle` includes: background type (gradient/solid/transparent), gradient colors + angle, padding %, shadow params, corner radius, device frame, aspect ratio. Implemented via Core Graphics / Core Image (GPU-accelerated). Unit-tested via pixel-diff snapshot tests.
- **Device Frame Renderer** — pure function. Renders generic Mac window / iPhone / Browser chrome around content. Mac and Browser variants support "replace original chrome" mode (default) and "keep original chrome" mode (toggle). Browser variant exposes editable faux URL field. Unit-tested.
- **Splitter** — pure function. Takes a tall image and N (or custom cut points), returns N images. Unit-tested.
- **Vibe Library** — data + applier. Each vibe = named bundle of `BeautifyStyle` values. Starter set: **Auto** (sampled 2-color gradient default) + 5 Pokémon energy types — **Grass** (organic, forest greens), **Electric** (yellows/blacks/electric blues), **Psychic** (dreamy, psychedelic), **Fairy** (baroque/Renaissance pinks/creams), **Steel** (brushed metal sheen, Nothing-phone tech-metallic). Each ships in v1 as a 2-color gradient palette that evokes the type's larger sensibility; richer thematic execution (textured/procedural backgrounds beyond gradient) deferred to v2. User-saved custom vibes persist via Settings Store (the `[+]` button on the picker strip). Unit-tested.
- **Library Store** — manages persistent capture library. Schema: each capture = one image file on disk + one row in a SQLite index. Row fields: `id`, `filename`, `relative_path`, `captured_at` (ISO timestamp), `capture_mode` (region|window|scrolling), `output_mode` (raw|beautified), `source_app_bundle_id` (nullable), `file_size_bytes`. Optional pre-rendered thumbnail cache at small size for fast grid rendering. Date-grouping logic computed at query time. Filename search via SQLite LIKE in v1 (no FTS). Unit-tested with temp directories.

### Modules (UI / coordination)

- **Menu Bar Surface** — `NSStatusItem` with a popover containing three direct capture buttons (Region / Window / Full Page), a divider, then "Show Library," "Settings…," and "Quit." Capture buttons inherit the sticky session Raw/Beautified mode (no separate toggle on this surface — that lives only on the hotkey picker). Idle and active icon states.
- **Hotkey Listener** — global hotkey via Carbon `RegisterEventHotKey` (the standard pattern; SwiftUI/AppKit don't provide first-class global hotkeys). Default: `⌘⇧7`. Configurable in Settings.
- **Picker Overlay** — borderless transparent window covering all screens, showing the capture-mode picker (Region / Window / Full Page buttons + sticky Raw/Beautified toggle). Dismisses on Escape or capture start.
- **Region Selector Overlay** — borderless window for the drag-to-select-region interaction.
- **Window Highlighter Overlay** — borderless window covering all screens. Cursor becomes a custom camera icon carrying Lightscreen's iconography (glyph designed during Figma mocks). Hovered window gets a soft holographic shimmer outline (system accent color underneath, foil-card sweep on hover-in — replaces Apple's flat blue rectangle). Click captures, Esc cancels (returns to nothing, not to the picker; user re-triggers ⌘⇧7 to retry). Only standard app windows are selectable; menu bars, dropdowns, tooltips, and floating panels are filtered out by `CGWindow` level. Works across all monitors. No screen dimming. Single open window still requires an explicit click (no auto-capture).
- **Auto-Scroll Recorder Overlay** — small floating indicator shown during auto-scroll, with progress and a Stop button.
- **Floating Preview Window** — bottom-right floating window (one per screen the cursor is on), 5-second auto-dismiss, draggable, clickable.
- **Editor Window** — SwiftUI window. Layout: top bar (back button, inline editable name field, Save button), vibe-picker strip below top bar, main canvas (left, fills available width), right sidebar with sections (Background / Image / Device frame / Ratio). Live preview, no Apply button.
- **Library Window** — SwiftUI window. Layout: top bar (search field, view mode dropdown, sort dropdown), main grid (date-grouped thumbnails with hover overlays), bottom status (count + storage).
- **Save Popover** — Apple Preview-style popover (Name, Tags, Where dropdown). Triggered by floating-preview click (Raw flow) or editor Save button (Beautified flow). Tags field maps to macOS Finder tags via NSURL resource keys.
- **Settings Window** — SwiftUI window with sections: General (hotkey, default ratio, default mode), Library (pin/unpin destination folders, storage stats, "Review now" trigger), Beautify (default vibe, edit/manage custom vibes, sound on/off, particles on/off), Permissions (Screen Recording, Accessibility status with link to System Settings).
- **Review Scheduler** — background timer (or launch-time check) that, when `last_review_prompt_at` is >60 days old, presents a non-blocking notification or library banner prompting review. No auto-action — user dismisses or opens library.
- **Settings Store** — `UserDefaults` (or a JSON file in Application Support) for user preferences. Stores: hotkey binding, default aspect ratio, default mode, sound on/off, particles on/off, system accent vs custom accent, pinned destinations, custom vibes, `last_review_prompt_at`.

### Visual identity (provisional)

- **Liquid Glass embraced fully** — translucent surfaces, frosted blur backgrounds, depth via shadow + blur layering.
- **Editor canvas surface = solid neutral** (decided: chrome uses glass, canvas stays solid so it doesn't compete with the screenshot for attention).
- **Personality:** playful, warm, Pokémon-coded.
- **Accent color:** follow macOS system accent by default; optional "energy type" palette (Water blue / Fire orange / Fairy pink / Electric yellow / Grass green / Psychic purple) selectable in Settings.
- **Typography:** SF Pro (Apple default).
- **Light + dark mode:** both, follow system.
- **Capture sparkle:** Holographic shimmer (foil-card sweep) across the preview surface + 2–3 small star particles flutter up and fade. Duration ~0.8s. Plays in the floating post-capture preview, **on capture only**. Save in the editor gets a quieter delight (Save button briefly glows, filename shimmer) — no full particles. Both toggleable in Settings, default on.
- **Sound feedback:** off by default; opt-in in Settings.
- **App name: Lightscreen** (provisional — to validate once icon and chrome appear in Figma). Named after the Pokémon screen move; reads accessibly to non-Pokémon fans (Lightroom-adjacent neighborhood). Vibe preset names follow Pokémon energy types (Auto + Grass / Electric / Psychic / Fairy / Steel).

### Flow decisions

- **Capture trigger:** Single hotkey `⌘⇧7` opens picker. Picker shows three mode buttons + sticky Raw/Beautified toggle. Clicking a mode immediately starts that capture.
- **Raw mode post-capture:** Floating preview appears bottom-right for 5 seconds. Drag → drops directly to destination, no library save. Click → opens save popover with default Where = library. Ignore → auto-saves to library after timeout.
- **Beautified mode post-capture:** Editor opens with default Auto vibe applied to the capture. User customises. Save button → save popover (default Where = library, overridable).
- **Splitting:** Available in editor only, surfaced when the capture is taller than the current aspect ratio. Live preview with draggable cut lines. Saves as numbered sequence to a single destination.

### Schema

**Library index (SQLite):**

```
captures
  id                    INTEGER PRIMARY KEY
  filename              TEXT NOT NULL          -- display name, user-editable
  relative_path         TEXT NOT NULL UNIQUE   -- under Application Support/.../captures/
  captured_at           TEXT NOT NULL          -- ISO 8601
  capture_mode          TEXT NOT NULL          -- region|window|scrolling
  output_mode           TEXT NOT NULL          -- raw|beautified
  source_app_bundle_id  TEXT                   -- nullable
  file_size_bytes       INTEGER NOT NULL

settings
  key                   TEXT PRIMARY KEY
  value                 TEXT NOT NULL          -- JSON for complex values
```

**Settings (UserDefaults or JSON):**

- `hotkey_binding`: keycode + modifier mask
- `default_aspect_ratio`: enum (16:9 default on first launch; sticky thereafter)
- `default_capture_mode`: enum (sticky)
- `default_output_mode`: enum (beautified default on first launch; sticky)
- `pinned_destinations`: array of folder paths
- `custom_vibes`: array of named BeautifyStyle blobs
- `sound_on_capture`: bool (default false)
- `sound_on_save`: bool (default false)
- `particles_on_capture`: bool (default true)
- `particles_on_save`: bool (default true)
- `accent_mode`: enum (system | energy-type)
- `accent_color`: enum (if energy-type)
- `last_review_prompt_at`: ISO timestamp

### Permissions required (one-time prompts)

- **Screen Recording** — required for ScreenCaptureKit. Prompted on first capture attempt; deep-link to System Settings if denied.
- **Accessibility** — required for Auto-Scroll Driver (scroll-event dispatch into target apps). Prompted on first scrolling capture attempt; deep-link if denied.

## Testing Decisions

### Test philosophy

- **Test external behavior, not implementation details.** A test should describe what the module promises to its callers, not how it does it. If we refactor internals, tests stay green.
- **Pure-function modules get the most tests** — Image Stitcher, Color Sampler, Beautify Renderer, Device Frame Renderer, Splitter, Vibe Library. They have well-defined inputs and outputs, no side effects, no UI.
- **Visual / pixel correctness via snapshot tests.** For renderers, render to PNG and pixel-diff against an approved reference image. Reference images live under `Tests/__snapshots__/`. When the design intentionally changes, regenerate references explicitly.
- **Stateful modules (Library Store) get integration tests against temp directories** — verifies real SQLite + filesystem behavior without polluting the user's data.
- **UI code is manually tested + minimal Xcode UI tests** for the critical end-to-end flows (hotkey → picker → capture → save).

### Modules with tests in v1

- **Image Stitcher** — fixture frame sequences with and without sticky headers; verifies stitched output dimensions and dedup correctness.
- **Color Sampler** — fixture images with known dominant colors; verifies extracted colors are within tolerance.
- **Beautify Renderer** — snapshot tests across the matrix of (background type × shadow on/off × corners × frame × ratio).
- **Device Frame Renderer** — snapshot tests for each frame type, both with chrome-replace and chrome-keep modes.
- **Splitter** — input image with known content; verifies N panels split at correct y-coordinates.
- **Vibe Library** — verifies each preset applies the expected BeautifyStyle; verifies custom vibes round-trip through save/load.
- **Library Store** — CRUD against temp directory; date grouping logic; filename search; index/file consistency under partial-failure scenarios.

### Modules with light or integration tests only in v1

- Capture Engine, Auto-Scroll Driver — integration tests against a controlled fixture app where feasible; otherwise rely on manual QA.
- Save Pipeline — integration tests for file-write correctness; popover behavior manually tested.
- Editor / Library / Settings windows — manually tested + a small number of UI snapshot tests for key states (empty, populated, error).
- Hotkey Listener, Menu Bar Surface, Picker Overlay, floating Preview — manually tested.

### Prior art

None — this is a brand-new project. Test framework: **Swift Testing** (the modern macro-based framework, standard in the Tahoe 26 era). XCTest used where Swift Testing doesn't cover (UI tests).

## Out of Scope

The following are explicit v1 exclusions. Each can return as v2+ if Atle's daily use surfaces the need.

- iOS / iPadOS companion apps
- Cloud sync, cloud upload, shareable links
- Accounts, sign-in, team features, multi-user
- AI-generated naming via Foundation Models
- AI-generated semantic search over library content
- Automatic PII detection / auto-redaction
- Manual annotation tools (arrows, text labels, step counters, highlights, blur/pixelate)
- OCR text extraction
- Video / screen recording capture
- Timed / delayed captures (countdown before snap)
- Freeze-screen capture mode (for grabbing menus that disappear on click)
- Full-screen capture mode (Atle keeps Apple's `⌘⇧3` for that)
- Additional device frames: iPad, MacBook full-laptop frame, Apple Watch, Android phones, Windows PC
- Watermarks, text overlays, captions in the editor
- Multi-image compositions on one canvas
- Image backgrounds (only gradient / solid / transparent in v1)
- Library: tags, sub-folders, favorites/stars, batch export, comparison view, semantic search
- App Store submission, distribution beyond personal use, code signing for distribution
- Internationalization / localization
- Auto-update mechanism
- Hotkey customization UI (default `⌘⇧7` only in v1; can be added later)
- Per-mode separate hotkeys (single picker hotkey only in v1)

## Further Notes

- **Build path:** Atle + Claude collaboratively. Claude writes the Swift code; Atle steers, tests on his Mac, gives feedback. Atle is not a developer — see `/Users/atle/.claude/projects/-Users-atle-Documents-Claude/memory/user_role.md` for collaboration norms (plain English, no jargon, aesthetics matter unusually much).
- **Naming and final identity decisions are still open** at the time of PRD writing. Atle is choosing between Sketch / Smeargle / Aurora (or another Pokémon-coded option). The name affects bundle identifier, About box, menu bar tooltip, and Settings header. Project folder may be renamed once the name is locked. Vibe preset names (Auto + 5 others) similarly depend on whether Atle accepts the Pokémon-type-coded naming for presets.
- **Performance target:** match or beat Shottr's ~17ms capture latency. Apple Silicon-native, no Rosetta. Region capture should feel as fast as Apple's `⌘⇧4`.
- **No GitHub / Linear / Jira / ClickUp project exists yet.** When one is set up, this PRD should be the first issue/spec ingested, and `ready-for-agent` applied at that time.
- **Design conversation origin:** Decisions in this PRD trace back to a `/grill-me` session captured in `/Users/atle/.claude/projects/-Users-atle-Documents-Claude/memory/project_screenshot_app.md`. That file is the running design memory; this PRD is the consolidated, build-ready synthesis.
- **Next steps after PRD acceptance:**
  1. ✅ App name locked: **Lightscreen** (provisional). Vibe preset naming locked: Auto + Grass / Electric / Psychic / Fairy / Steel.
  2. **Build a Pokémon-coded Liquid Glass design system in Figma** — type-color tokens, vibe thumbnail component, capture-button component, library cell component, floating action bar component.
  3. Mock the 8 V1 surfaces in Figma using that system: capture picker, menu bar dropdown, floating post-capture preview (Raw + Beautified variants), editor, save popover, library (incl. multi-select state, empty state, 60-day banner), settings window, system surfaces (app icon, menu bar icon idle+active, permissions sheets).
  4. Set up the Xcode project (Swift + SwiftUI, Tahoe 26 deployment target).
  5. Initialise the project's `CLAUDE.md` via `/init`.
  6. Implement modules in roughly this order, since each enables the next: Library Store → Capture Engine (region first) → Save Pipeline → Floating Preview → Beautify Renderer → Editor Window → Vibe Library → Device Frame Renderer → Window Capture → Auto-Scroll Driver → Image Stitcher → Splitter → Library Window → Settings → Review Scheduler → identity polish (particles, shimmer, voice).
- **Risk to flag:** Auto-Scroll (Approach A) was chosen against my recommendation. The "Retry manually" rescue button is the agreed mitigation. If during build it becomes clear auto-scroll fails too often to be the v1 default, fall back to Approach B (manual scroll capture) and surface as a finding before shipping.
