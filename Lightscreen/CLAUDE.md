# CLAUDE.md

## Tech stack
- Swift + SwiftUI (macOS app)
- macOS Tahoe 26 minimum deployment target

## File conventions
- `Modules/`: pure logic types and helpers. Prefer deterministic, side-effect-free code.
- `UI/`: SwiftUI views (kept empty until Stage 1+).
- `Resources/`: app assets and icons.
- `App/`: application entry point and AppKit interop (menu bar wiring, global surfaces).
- Comments must be in plain English with “what it feels like” context when relevant. Avoid jargon.

## Design references
- PRD: `../PRD.md`
- Running memory (project context): `../.claude/projects/-Users-atle-Documents-Claude/memory/project_screenshot_app.md`

