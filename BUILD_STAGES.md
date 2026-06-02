# Lightscreen — Build Stages

> **Purpose:** Break the PRD into 14 ordered stages that Cursor's agent can execute one at a time. Each stage produces something Atle can test on his Mac before moving to the next.
> **Companion doc:** `PRD.md` (the full spec). This file is the *implementation order* and *acceptance tests*.
> **Status:** 2026-06-02 — stages defined, none started.

---

## How to use this document with Cursor

For each stage, paste the following template into Cursor's Composer (Agent mode), filling in the stage number and title:

```
Read these files first:
- /Users/atle/Documents/Claude/Projects/Screenshot App/PRD.md  (full spec)
- /Users/atle/Documents/Claude/Projects/Screenshot App/BUILD_STAGES.md  (this file)
- /Users/atle/.claude/projects/-Users-atle-Documents-Claude/memory/project_screenshot_app.md  (running design memory)
- /Users/atle/.claude/projects/-Users-atle-Documents-Claude/memory/user_role.md  (how Atle works — plain English, designer not developer)

Then implement Stage [N]: [Title]. Follow the "Implement" list exactly. Do not skip ahead to a future stage's scope.

Tech stack: Swift + SwiftUI on macOS Tahoe 26 minimum. Use AppKit interop only where SwiftUI can't reach (global hotkey, menu bar item, overlay windows).

When done, give me a numbered manual test plan I can run on my Mac to verify the "Acceptance test" criteria from this stage. Then stop — do not start the next stage.

If anything in the stage is ambiguous, ASK before writing code.
```

**Workflow between stages:**
1. Run the stage in Cursor
2. Walk through the manual acceptance test on your Mac
3. If pass → commit + push (`git commit -m "Stage N: [title]"`)
4. If fail → tell Cursor what didn't work; it iterates
5. Move to the next stage

---

## Stage roadmap (14 stages)

| # | Title | What you can do at the end |
|---|---|---|
| 0 | Project scaffolding | App launches, menu bar icon appears, nothing else yet |
| 1 | Hotkey + capture picker overlay | ⌘⇧7 opens the picker; three buttons visible (none functional yet) |
| 2 | Region capture + Library Store | ⌘⇧7 → Region → drag a box → image saved to library on disk |
| 3 | Floating preview + save popover | Full Raw flow works end-to-end (capture → preview → save/drag/ignore) |
| 4 | Menu bar dropdown | Capture can also be triggered from the menu bar |
| 5 | Library window | Can see your catches in a grid, search, hover quick actions |
| 6 | Window capture | ⌘⇧7 → Window → hover → click → clean window capture |
| 7 | Beautify Renderer + basic editor | Beautified mode applies a gradient + shadow + padding |
| 8 | Vibe library + picker strip | Switch between Auto + 5 type vibes in the editor |
| 9 | Device frames + aspect ratios + split | Editor produces social-ready output in any ratio |
| 10 | Scrolling capture + image stitcher | ⌘⇧7 → Full Page → captures a whole webpage |
| 11 | Library multi-select + 60-day prompt | Bulk delete/move catches; cleanup reminders work |
| 12 | Settings window | Customize hotkey, defaults, toggles, accent color |
| 13 | Identity polish | Sparkle on capture, voiced copy, Liquid Glass, final icons |

---

# Stages

## Stage 0 — Project scaffolding

**Goal:** Create a launchable Xcode project that lives in the menu bar (no dock icon) and does nothing else.

**Builds on:** Nothing.

**Implement:**
- Create new Xcode project: macOS App, Swift + SwiftUI, name `Lightscreen`, deployment target macOS 26.0.
- Set `LSUIElement = true` in `Info.plist` so the app runs as a menu bar–only accessory (no dock icon).
- Add `NSStatusItem` with a temporary placeholder icon (SF Symbol `camera.fill` will do for now).
- Folder structure:
  - `Lightscreen/Modules/` (pure-logic modules — empty for now)
  - `Lightscreen/UI/` (SwiftUI views — empty for now)
  - `Lightscreen/Resources/` (assets, icons)
- Create `CLAUDE.md` at the project root with: tech stack, file conventions, link to PRD + memory file, "plain English in comments, no jargon."
- Set up `.gitignore` (Xcode default).
- Initialize git, first commit "Stage 0: scaffolding."

**Acceptance test (run manually):**
1. Build & run in Xcode.
2. A camera icon appears in the menu bar.
3. **No** app appears in the dock.
4. Clicking the menu bar icon does nothing yet (that's correct).
5. Quit via Cmd+Q from the menu bar icon's right-click or from Xcode.

**PRD references:** Implementation Decisions → Architecture · Modules (UI/coordination) → Menu Bar Surface.

---

## Stage 1 — Hotkey + capture picker overlay

**Goal:** Pressing ⌘⇧7 anywhere on the Mac opens a centered overlay with three capture buttons and a Beautified ↔ Raw toggle. Buttons don't trigger captures yet.

**Builds on:** Stage 0.

**Implement:**
- **Hotkey Listener** module — use Carbon `RegisterEventHotKey` API to register ⌘⇧7 globally. (This is the standard pattern; SwiftUI doesn't expose global hotkeys.)
- **Picker Overlay** — borderless transparent window covering all screens. Liquid Glass background material.
  - Three capture-mode buttons in a row: Region · Window · Full Page (use SF Symbols `rectangle.dashed`, `macwindow`, `arrow.down.doc.fill` as placeholders).
  - Below the buttons: a sticky toggle for **Beautified ↔ Raw**. Default state = Beautified.
  - Esc dismisses; clicking outside dismisses; clicking a button dismisses (and prints to console for now — "Region clicked").
- Persist the Raw/Beautified toggle across sessions via `UserDefaults` (key: `default_output_mode`).
- The picker auto-dismisses when any capture begins (will matter in Stage 2).

**Acceptance test:**
1. Build & run. Press ⌘⇧7 from anywhere (try while in Safari, Finder, Slack).
2. Picker overlay appears centered with frosted glass background.
3. All three buttons + the toggle are visible.
4. Click each button — observe a console log; picker dismisses.
5. Toggle Raw/Beautified, dismiss picker, re-open with ⌘⇧7 — toggle remembers its state.
6. Press Esc to dismiss — picker disappears, no console error.

**PRD references:** User stories 1–6 · Implementation Decisions → Hotkey Listener, Picker Overlay.

---

## Stage 2 — Region capture + Library Store

**Goal:** ⌘⇧7 → Region → drag a rectangle → captured image saves to disk, indexed in SQLite.

**Builds on:** Stages 0, 1.

**Implement:**
- **Library Store** module:
  - Storage path: `~/Library/Application Support/Lightscreen/captures/`.
  - SQLite index (`captures.db` at the parent path) with the schema from PRD's "Schema" section.
  - CRUD: `insert(capture)`, `fetchAll()`, `fetchByDateGroup()`, `delete(id)`, `move(id, toPath)`.
  - Computes date-grouping at query time (Today / Yesterday / Earlier this week / Last week / Earlier).
- **Capture Engine** module — wraps `ScreenCaptureKit`.
  - `CaptureRequest.region(rect: CGRect)` → returns `Data` (PNG).
- **Region Selector Overlay** — borderless transparent window across all screens.
  - Cursor becomes crosshair.
  - Drag to draw a selection rectangle (live highlight + dimensions readout in the corner).
  - Release mouse = capture happens; overlay dismisses.
  - Esc cancels without capturing.
- Wire up: picker's "Region" button → dismisses picker → opens Region Selector → captured image saves to library with filename `Screenshot YYYY-MM-DD at HH.MM.SS.png`.

**Acceptance test:**
1. Press ⌘⇧7 → click Region.
2. Crosshair appears; drag a box over part of your screen.
3. Release — selection disappears.
4. Open Finder, navigate to `~/Library/Application Support/Lightscreen/captures/`.
5. The new PNG is there. Open it — content matches what you selected.
6. Press ⌘⇧7 → Region → press Esc midway through drag — no file is created.

**PRD references:** User stories 7–8 · Implementation Decisions → Capture Engine, Library Store, Region Selector Overlay · Schema.

---

## Stage 3 — Floating preview + save popover (Raw flow complete)

**Goal:** After capture, a small preview slides in bottom-right. You can drag it out, click to save, or ignore (auto-saves to library).

**Builds on:** Stages 0–2.

**Implement:**
- **Floating Preview Window** — borderless window, bottom-right of the active screen (one per screen the cursor is on).
  - Shows the just-captured thumbnail (rounded corners + soft shadow + frosted glass surround).
  - Auto-dismisses after 5 seconds.
  - Drag → starts a drag-drop session; image data goes to the destination (Finder, Messages, any drop target).
  - Click → opens the Save Popover (next bullet).
  - 5-sec timeout with no interaction → auto-saves to library (Raw mode).
- **Save Popover** — Apple Preview-style.
  - Name field (pre-filled with default filename, editable).
  - Tags field (maps to macOS Finder tags via `NSURL` resource keys).
  - "Where" dropdown:
    - Default: "Lightscreen library" (the app's library folder).
    - Recent folders the user has used (track via `UserDefaults`, max 5).
    - "Other…" → opens `NSOpenPanel` for full Finder picker.
  - Save button commits the file + writes/updates the SQLite row.
- **Note:** This stage handles only **Raw mode**. Beautified mode (which opens the editor) comes in Stage 7. For now, if the toggle is on Beautified, behave as Raw (we'll wire the editor later).

**Acceptance test:**
1. Press ⌘⇧7 → Region → drag a box → release.
2. A floating thumbnail appears bottom-right with the captured image.
3. **Test ignore:** Wait 5 seconds. It disappears. Open Library Store path — image is saved.
4. **Test click-to-save:** Capture again → click the floating thumbnail → save popover appears with editable name, tags, and a "Where" dropdown.
5. **Test drag:** Capture again → drag the thumbnail into a Finder window → image file lands in that folder.
6. **Test cancel save:** Open save popover → press Esc → popover closes, no file saved at that path.

**PRD references:** User stories 18–22, 40–44 · Implementation Decisions → Floating Preview Window, Save Popover.

---

## Stage 4 — Menu bar dropdown

**Goal:** Clicking the menu bar icon opens a popover with three direct capture buttons + library/settings/quit.

**Builds on:** Stages 0–3.

**Implement:**
- Update **Menu Bar Surface** module:
  - Popover layout (top to bottom):
    1. Three capture buttons in a row: Region · Window · Full Page (same icons as picker).
    2. Divider.
    3. "Show Library" (stub — opens an empty window for now; real one in Stage 5).
    4. "Settings…" (stub).
    5. "Quit Lightscreen" (functional).
  - Capture buttons inherit the sticky session Raw/Beautified mode (no separate toggle on this surface).
  - Clicking Region works (same flow as Stage 2). Window and Full Page = no-op stubs until Stages 6 and 10.

**Acceptance test:**
1. Click the menu bar icon.
2. Popover appears under the icon with all five items visible.
3. Click "Region" → popover dismisses → Region Selector opens → capture flow works (same as hotkey).
4. Click Window or Full Page → popover dismisses → nothing else happens (will be wired in future stages).
5. Click "Quit Lightscreen" → app exits.

**PRD references:** Implementation Decisions → Menu Bar Surface · `project_screenshot_app.md` → Capture flow.

---

## Stage 5 — Library window

**Goal:** A library window that shows all your catches as a date-grouped grid with hover quick actions, search, and a bottom status bar.

**Builds on:** Stages 0–4.

**Implement:**
- **Library Window** — SwiftUI window.
  - Top bar: search field (filename text-match), sort dropdown (Newest first / Oldest first), view-mode dropdown (grid only in v1 — placeholder for future list view).
  - Main area: grid of thumbnail cells (target ~180×120pt per cell), date-grouped with sticky section headers (Today / Yesterday / Earlier this week / Last week / Earlier).
  - Each cell shows the thumbnail + filename below.
  - **Hover state:** cell grows slightly, gains a soft shadow, and shows 4 quick-action icons (Open in editor [stub], Reveal in Finder, Move to…, Delete).
  - **Double-click** = stub for now (will open the editor in Stage 7).
  - **Drag thumbnail out** = drag-drop session → image data to destination.
  - **Right-click context menu** mirrors the hover actions.
  - Bottom status bar: "N catches · X.X MB total" (computed from Library Store).
- **Empty state:** voiced copy, time-of-day aware:
  - 5am–11am: "Morning. No catches yet — try ⌘⇧7."
  - 11am–5pm: "Afternoon. No catches yet — try ⌘⇧7."
  - 5pm–10pm: "Evening. No catches yet — try ⌘⇧7."
  - 10pm–5am: "Late night. No catches yet — try ⌘⇧7."
- Wire menu bar → "Show Library" to open this window.

**Acceptance test:**
1. Click menu bar icon → "Show Library" → window opens.
2. **First-time empty state:** if library is empty, shows the voiced copy matching the time of day.
3. Capture 5–10 things (Region) → reopen Library → all visible, grouped by date.
4. Hover a thumbnail → it grows slightly, shows the 4 quick-action icons.
5. Click "Reveal in Finder" → Finder opens with the file selected.
6. Click "Delete" → file removed (no confirmation in v1 single-delete).
7. Type a filename fragment in search → grid filters down.
8. Drag a thumbnail into a Finder window → file copies to that folder.
9. Bottom bar shows correct count + storage size.

**PRD references:** User stories 45–54, 68 · Implementation Decisions → Library Window.

---

## Stage 6 — Window capture

**Goal:** ⌘⇧7 → Window → hover any open window → see a soft holographic shimmer outline → click to capture cleanly.

**Builds on:** Stages 0–5.

**Implement:**
- **Window Highlighter Overlay** — borderless window across all screens.
  - Cursor becomes a custom camera icon (use a temporary glyph — finalized in Stage 13).
  - Use `CGWindowListCopyWindowInfo` filtered to standard app windows (skip menu bars, dropdowns, tooltips, floating panels — filter by `kCGWindowLayer == 0`).
  - On hover, draw a soft holographic shimmer outline around the window under the cursor:
    - Border = ~3pt, system accent color underneath
    - Foil-card sweep animation on hover-in (~250ms gradient sweep across the outline)
    - Crisp corner radius matching the window
  - Click captures the window via `ScreenCaptureKit.SCContentFilter(desktopIndependentWindow:)`.
  - Esc cancels → returns to nothing (NOT back to the picker). User re-triggers ⌘⇧7 to retry.
  - Works across all displays.
  - **No screen dimming** — Apple doesn't dim either; the outline is enough.
  - Single open window still requires explicit click (no auto-capture).
- Captured window goes through the Stage 3 Raw flow (floating preview → save).

**Acceptance test:**
1. Open 3–4 different apps. Press ⌘⇧7 → click Window.
2. Custom cursor appears. Move it over Safari → shimmer outline draws around Safari.
3. Move it over the menu bar → no outline (filtered out).
4. Move to a small floating window or popover → no outline.
5. Click on the highlighted Safari window → capture happens → floating preview appears.
6. Captured image contains the window cleanly (window content + macOS shadow).
7. Press ⌘⇧7 → Window → press Esc — nothing happens, you're back to normal.
8. Try with a second monitor connected — outline works on both displays.

**PRD references:** User stories 9–14 · Implementation Decisions → Window Highlighter Overlay · `project_screenshot_app.md` → Window capture selection UX.

---

## Stage 7 — Beautify Renderer + basic editor

**Goal:** When the picker is set to Beautified, capture → editor opens → image appears on a soft gradient background with shadow and padding. Save commits the styled output.

**Builds on:** Stages 0–6.

**Implement:**
- **Color Sampler** (pure function): image → top 2 dominant colors weighted by area, skipping near-duplicates, preferring saturated.
- **Beautify Renderer** (pure function): `(image, BeautifyStyle)` → rendered PNG. Use Core Graphics / Core Image. `BeautifyStyle` includes:
  - `background`: enum `gradient(c1, c2, angle) | solid(c) | transparent`
  - `padding`: percent (0–25%, default 10%)
  - `shadow`: struct `{ enabled, blur, yOffset, opacity }` (default soft: 40px blur, 10px Y, 20% opacity)
  - `cornerRadius`: int (0–32, default 12)
  - (device frame, aspect ratio, vibe → added in Stages 8, 9)
- **Editor Window** — SwiftUI.
  - Layout per PRD: left = live canvas (fills available width), right sidebar = controls, top bar = editable filename + back button + Save button.
  - **For Stage 7, the right sidebar contains only:**
    - Background section: gradient (default, auto-sampled) / solid / transparent radio · color stops · angle slider
    - Image section: padding slider, shadow toggle + intensity, corners slider
  - Live preview — no Apply button. Every slider change re-renders.
  - Save button → save popover (same shape as Stage 3) → commits the *rendered* PNG to library.
- Wire the picker's Beautified mode to open the editor instead of the floating preview.
- Wire the library's double-click + "Open in editor" quick action to open any past capture in the editor.

**Acceptance test:**
1. Toggle picker to Beautified. Press ⌘⇧7 → Region → drag.
2. Editor opens. Captured image is centered on a 2-color gradient background sampled from the image itself.
3. Drag padding slider → image scales smaller; gradient frame fills the gap.
4. Toggle shadow off → shadow vanishes. Toggle back on → it returns.
5. Adjust corner radius slider → image corners round.
6. Switch background to "solid" → solid color picker appears.
7. Switch to "transparent" → background becomes checkerboard transparency.
8. Click Save → save popover appears → save to library → file is the *styled* output (not the raw screenshot).
9. Open a past Raw capture from the library (double-click) → it opens in the editor with default beautification applied.

**PRD references:** User stories 23–32 · Implementation Decisions → Color Sampler, Beautify Renderer, Editor Window.

---

## Stage 8 — Vibe library + picker strip

**Goal:** Top of the editor shows a horizontal strip of vibe thumbnails. Click a vibe to instantly retheme the background. Save your own custom vibes.

**Builds on:** Stages 0–7.

**Implement:**
- **Vibe Library** module:
  - Built-in vibes (locked):
    - `Auto` — uses Color Sampler output (current behavior)
    - `Grass` — organic gradient (forest greens, soft warm light)
    - `Electric` — yellows/blacks/electric blues
    - `Psychic` — dreamy psychedelic purples/pinks
    - `Fairy` — baroque pinks/creams (Renaissance palette)
    - `Steel` — brushed metal gradient (cool grays, subtle sheen)
  - Each vibe = a `BeautifyStyle` blob with hardcoded gradient colors (or sampling rules for Auto).
  - User-saved custom vibes persist in `UserDefaults` (or a JSON file in Application Support) as `[CustomVibe]`.
- **Vibe picker strip** at the top of the editor.
  - 7 slots in v1: Auto + 5 type vibes + `[+]` custom button.
  - Each thumbnail = rendered preview of the *current* screenshot with that vibe applied (so the user is comparing the actual output).
  - Small type-icon overlay in the corner of each thumbnail (Auto gets a sparkle, types get a Pokémon-type symbol — temporary glyphs OK until Stage 13).
  - **Active state:** bold border in the type's accent color (Grass=green, Electric=yellow, Psychic=purple, Fairy=pink, Steel=silver) + unselected thumbnails fade to ~70% opacity.
  - **Overflow:** horizontal scroll with a fade mask on the right edge.
- `[+]` button → small dialog: "Name this vibe" → saves current `BeautifyStyle` as a custom vibe (appears in the strip alongside built-ins; right-click to rename/delete).

**Acceptance test:**
1. Press ⌘⇧7 → Region (Beautified) → editor opens.
2. Vibe strip at top shows 7 thumbnails — each rendered with the current screenshot.
3. Click Grass → background changes to green gradient instantly; Grass thumbnail gets a green border, others fade.
4. Click through each vibe → each applies its palette.
5. Adjust the gradient angle manually → click `[+]` → name it "Sunset Hero" → it appears in the strip.
6. Click Steel, then click your custom Sunset Hero → it restores your saved palette.
7. Right-click Sunset Hero → "Delete vibe" → it disappears.
8. Close editor and reopen on a different capture → vibe thumbnails re-render against the new image.

**PRD references:** User stories 25–26 · Implementation Decisions → Vibe Library · `project_screenshot_app.md` → Beautified editor.

---

## Stage 9 — Device frames + aspect ratios + split into

**Goal:** Editor sidebar now has Device frame + Ratio sections. Tall captures get a "Split into…" button.

**Builds on:** Stages 0–8.

**Implement:**
- **Device Frame Renderer** (pure function): wraps image in chrome. Options:
  - `None`
  - `Mac window` — title bar with three traffic-light dots, no app icon, no text in title (privacy-safe by default)
  - `iPhone` — generic iPhone bezel (Dynamic Island variant)
  - `Browser` — generic browser chrome with editable faux URL field, tab text always blank
  - "Keep original chrome" toggle (defaults to OFF — generic chrome by default)
- **Aspect ratio dropdown** in editor — 8 options:
  - 16:9 (Twitter, default on first launch)
  - 1:1 (Instagram)
  - 4:5 (Instagram portrait)
  - 9:16 (Stories/Reels/TikTok)
  - 3:2 (Dribbble)
  - 1.91:1 (LinkedIn/OG)
  - Original
  - Custom (with width × height fields)
  - **Sticky:** last-used ratio is remembered for next session.
- **Splitter** (pure function): tall image + N (or custom cut points) → array of N images.
- **"Split into…" button** in editor — appears only when the capture is taller than the current aspect ratio.
  - Clicking shows options: 2 / 3 / 4 / Custom panels.
  - Live preview: cut lines drawn across the canvas. Drag a cut line to adjust position.
  - Save = saves N files as `name_01.png`, `name_02.png`, … to the chosen destination.

**Acceptance test:**
1. Open editor on a capture. Right sidebar now has all 4 sections (Background / Image / Device frame / Ratio).
2. Device frame → Browser → frame appears around the screenshot with a blank faux URL bar. Click the URL field → type "atle.design" → it shows.
3. Toggle "Keep original chrome" → browser chrome from the captured image returns (if any).
4. Change Device frame → Mac window → generic title bar appears.
5. Change ratio to 9:16 → canvas reshapes to portrait → image repositions cleanly.
6. Capture a tall scrolling page (or use a known-tall image) → set ratio 16:9 → "Split into…" button appears.
7. Click → choose 3 panels → cut lines preview. Drag the middle cut line → it moves.
8. Save → 3 files appear in your destination: `name_01.png`, `name_02.png`, `name_03.png`.
9. Close editor, reopen on a new capture → ratio is still 9:16 (sticky).

**PRD references:** User stories 33–39 · Implementation Decisions → Device Frame Renderer, Splitter.

---

## Stage 10 — Scrolling capture + image stitcher

**Goal:** ⌘⇧7 → Full Page → app auto-scrolls a window and stitches the frames into one tall image. "Retry manually" rescue if auto fails.

**Builds on:** Stages 0–9.

**Implement:**
- **Auto-Scroll Driver** module — drives scroll via macOS Accessibility API + `CGEventCreateScrollWheelEvent`.
  - Detects the active scrollable region in the target window.
  - Captures frames at intervals as it scrolls.
  - Returns: ordered frames + success flag.
  - Requires Accessibility permission (prompt + System Settings deep-link).
- **Image Stitcher** (pure function): ordered overlapping frames → one tall image.
  - Detect and dedupe sticky headers (compare top N pixels across consecutive frames; if identical, crop from the second).
  - Detect and dedupe sticky footers (same logic for bottom).
  - Output: single tall PNG.
- **Auto-Scroll Recorder Overlay** — small floating indicator during auto-scroll:
  - Progress bar + Stop button.
  - Shown over the target window.
- After auto-scroll finishes:
  - Show a quick preview with "Retry manually" button (rescue path — opens a manual scroll-and-capture UI for tricky pages).
- Tall captures auto-default the editor's aspect ratio to "Original."

**Acceptance test:**
1. Open Safari, navigate to a long page (e.g., a news article).
2. Press ⌘⇧7 → click Full Page.
3. App prompts for Accessibility permission if not granted → go through the System Settings flow.
4. After granting, repeat: ⌘⇧7 → Full Page → app starts auto-scrolling Safari → recorder overlay shows progress.
5. After completion, preview shows the stitched tall image. No duplicated sticky header (e.g., the site nav appears once at the top, not at every scroll position).
6. Save → floating preview → save flow.
7. Open editor on the tall capture → ratio defaults to "Original" automatically.
8. Try a page with a known-bad sticky header → press "Retry manually" → manual recovery flow works.

**PRD references:** User stories 15–17 · Implementation Decisions → Auto-Scroll Driver, Image Stitcher, Auto-Scroll Recorder Overlay.

---

## Stage 11 — Library multi-select + 60-day prompt

**Goal:** cmd-click / shift-click in the library to multi-select. Floating action bar appears at the bottom with Move to / Delete / Deselect. 60-day prompt fires in two surfaces.

**Builds on:** Stages 0–10.

**Implement:**
- **Multi-select mechanics** in Library Window:
  - cmd-click adds to selection
  - shift-click range-selects
  - cmd-A selects all
  - Esc deselects all
- **Visual:** small checkmark icon in the top-left corner of selected thumbs + system-accent border around the cell.
- **Bulk action bar** — floating, slides up from the bottom of the library window when ≥1 item selected:
  - Left: count ("3 catches selected")
  - Middle: "Move to…" + "Delete" buttons
  - Right: "Deselect all"
- **"Move to…" dropdown** = same shape as save popover's Where field (recent folders + "Other…").
- **Bulk delete confirmation:** small sheet "Delete 3 catches?" with destructive button styling. (Single-item delete from hover stays no-confirmation.)
- **Review Scheduler** module:
  - Background timer (or launch-time check) reads `last_review_prompt_at` from Settings Store.
  - When ≥60 days old, schedule a prompt.
  - **Two surfaces:**
    1. macOS system notification (via `UNUserNotificationCenter`).
    2. Banner across the top of the library window on next open.
  - **Voiced copy:** "You have a lot of catches. Want to release some?"
  - **Tap action:** opens the library window in multi-select mode pre-loaded for batch delete.
  - **Dismiss:** close button → updates `last_review_prompt_at` to now → next prompt fires in 60 days.

**Acceptance test:**
1. Open Library. cmd-click 3 thumbnails → each gets a checkmark + accent border. Bulk action bar slides up from the bottom showing "3 catches selected · Move to… · Delete · Deselect all".
2. shift-click a 4th → range fills in.
3. Click "Move to…" → dropdown shape matches the save popover's Where field. Pick a folder → files move, bar dismisses.
4. Multi-select 2 more → click Delete → confirmation sheet "Delete 2 catches?" → click Delete → files removed.
5. Click a thumbnail without modifier → all deselected → bar dismisses.
6. **60-day test:** in Settings (or DB directly), manually set `last_review_prompt_at` to 61 days ago. Quit and relaunch.
7. macOS system notification appears with the voiced copy.
8. Open the library window → banner across the top shows the same voiced copy.
9. Click the banner → library enters multi-select mode with all catches selected, ready for bulk delete.
10. Dismiss the banner → next prompt fires 60 days from now (verify by inspecting `last_review_prompt_at`).

**PRD references:** User stories 55, 68–74 · Implementation Decisions → Review Scheduler · `project_screenshot_app.md` → Multi-select / bulk operations + 60-day review prompt.

---

## Stage 12 — Settings window

**Goal:** A Settings window where you can rebind the hotkey, change defaults, toggle sound/sparkle, pin folders, and pick an accent.

**Builds on:** Stages 0–11.

**Implement:**
- **Settings Window** — SwiftUI window, sidebar-or-tabs layout. Sections:
  - **General**
    - Hotkey: editable shortcut field (default ⌘⇧7)
    - Default capture mode (region/window/full page) — sticky
    - Default output mode (raw/beautified) — sticky
    - Default aspect ratio dropdown — sticky
  - **Library**
    - Pinned destinations: list of folders + add/remove buttons
    - Storage stats: total size, count
    - "Review now" button → opens library in multi-select mode
  - **Beautify**
    - Default vibe override (dropdown of built-in + custom)
    - Manage custom vibes (rename/delete list)
    - Capture sound on/off (default off)
    - Sparkle on capture on/off (default on)
    - Save delight on/off (default on)
  - **Appearance**
    - Accent color: System (default) / Energy-type (radio: Water blue / Fire orange / Fairy pink / Electric yellow / Grass green / Psychic purple / Steel silver)
  - **Permissions**
    - Screen Recording status badge + "Open System Settings" button
    - Accessibility status badge + "Open System Settings" button
- All toggles update `UserDefaults` immediately (no Apply button).
- Wire menu bar → "Settings…" to open this window.

**Acceptance test:**
1. Click menu bar → Settings… → window opens with all sections visible.
2. **Hotkey rebind:** click the hotkey field → press ⌘⇧8 → it updates. Quit and relaunch — ⌘⇧8 now opens the picker, ⌘⇧7 doesn't.
3. Toggle sparkle off → capture something → no sparkle on the floating preview.
4. Set default vibe to "Fairy" → next Beautified capture opens editor with Fairy applied.
5. Pin a folder ("~/Desktop/Projects/Lightscreen") → next save popover shows it at the top of Where dropdown.
6. Change accent to "Electric (yellow)" → multi-select borders, active vibe accents, and other accent surfaces shift to yellow.
7. Permissions section accurately shows green/red badges for Screen Recording and Accessibility.

**PRD references:** User stories 64–67 (privacy/ownership underpinning) · Implementation Decisions → Settings Window, Settings Store, Permissions.

---

## Stage 13 — Identity polish

**Goal:** The app now *feels* like Lightscreen — sparkle on capture, voiced empty states, Liquid Glass everywhere, final icons.

**Builds on:** Stages 0–12.

**Implement:**
- **Capture sparkle:**
  - On capture (any mode) → floating preview plays a single shimmer pass across its surface (holographic foil sweep, ~0.8s) + 2–3 small star particles flutter up from the bottom and fade.
  - Skips entirely if user has toggled sparkle off in Settings.
- **Save delight (editor):**
  - On Save click in the editor → Save button briefly glows (radial bloom in current accent color) + filename in the top bar shimmers once.
  - Smaller scale than capture sparkle. Skips if toggled off.
- **Voiced copy throughout:**
  - Library empty state (time-of-day aware — already in Stage 5; verify polish)
  - 60-day banner (already in Stage 11; verify polish)
  - Settings sections gain warm one-liners ("Where your catches live", "How saving feels")
  - Permissions denial copy ("Lightscreen needs to peek at your screen — open System Settings?")
- **Liquid Glass pass:**
  - Audit every window/popover/overlay surface: picker, menu bar dropdown, floating preview, editor chrome (NOT canvas), library top/bottom bars, save popover, settings, bulk action bar.
  - Apply `NSVisualEffectView` with appropriate materials (`.hudWindow`, `.popover`, `.menu`, `.sidebar`) per surface.
  - Canvas in editor stays **solid neutral** (doesn't fight the screenshot for attention) — confirm.
- **Final icons:**
  - App icon (1024×1024 + all sizes) — Lightscreen-branded, Pokéball-cradling-a-screen motif (or whatever direction the Figma mocks land on).
  - Menu bar icon — idle state (line variant) + active state (filled / accent-tinted when a capture is in progress).
  - Custom cursor for window-capture mode (replaces the placeholder from Stage 6).
  - Type-icon glyphs for vibe thumbnails (replace placeholder SF Symbols).

**Acceptance test:**
1. Capture something → floating preview shimmers + stars flutter up. ~0.8 seconds total.
2. Click Save in editor → button glows briefly + filename shimmers.
3. Toggle sparkle off in Settings → no animations on next capture.
4. Empty library at 7am shows "Morning. No catches yet…" with the same warmth in Settings, banner, etc.
5. Every window/popover surface visibly uses Liquid Glass material. Canvas in the editor stays solid.
6. App icon shows correctly in Finder Get Info, Spotlight, Cmd+Tab.
7. Menu bar icon visibly changes between idle and active states during a capture.
8. Window-capture cursor uses the Lightscreen camera glyph (not the temp placeholder).
9. Vibe thumbnails show the final type-icon overlays (not SF Symbols).

**PRD references:** User stories 56–63 · Implementation Decisions → Visual identity · `project_screenshot_app.md` → Identity.

---

# After Stage 13

**Lightscreen v1 is shipped to you, on your Mac.** Everything in the PRD is built. Atle uses it daily; logs anything that should change.

**Post-v1 candidates** (already noted as out-of-scope but worth tracking):
- Tags / sub-folders / favorites in library
- Batch export from library
- AI naming (Foundation Models in Tahoe 26)
- PII detection / auto-redaction
- Annotation tools (arrows, text, blur)
- Timed / freeze captures
- iPad / Apple Watch / Android device frames
- Richer v2 vibe execution beyond gradients (procedural backgrounds, type-themed elements)
- Watermarks, image backgrounds, multi-image compositions
- Auto-update mechanism + code signing for distribution

---

**Doc owner:** Atle. **Updated:** 2026-06-02.
