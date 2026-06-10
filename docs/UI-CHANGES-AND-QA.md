# Interless UI/UX overhaul — change summary & QA checklist

This session reworked the design system, motion, layout persistence, personalization,
accessibility, and Settings. Everything was statically verified (brace/paren balance,
token resolution, no stray literals) but **not compiled** — these notes are to guide a
real build + visual/VoiceOver pass on macOS.

16 files changed (~490 insertions / ~167 deletions). New file: `UI/MotionPrimitives.swift`.

---

## What changed, by area

### 1. Color system — dual-accent identity (`DesignTokens.swift`)
- **Amber** (`accent`/`accent2`) = brand / user-driven actions (send, focus, selection).
- **Green phosphor** (`phosphor`/`phosphorGlow`) = "the machine is alive" — running agent,
  active sessions, streaming, live caret, telemetry. The deliberate Matrix nod.
- **Diff green/red** (`diffAdd`/`diffDel`) = diffs only, never reused.
- New status tokens `caution` / `danger` / `info` / `success` replace ad-hoc `.orange`/`.red`/`.blue`/`.green`.
- Light-mode accent/phosphor/accent2 darkened to clear WCAG AA; border alphas bumped for visible structure.

### 2. Motion (`MotionPrimitives.swift`, `ChatPaneView`, `SessionNavigatorView`)
- `BlinkingCaret` (phosphor terminal cursor) and `.pulsing()` modifier — **both honor Reduce Motion**.
- Streaming indicator → pulsing "generating" + blinking caret. Active-now session dot pulses.

### 3. Empty / first-run chat state (`ChatPaneView`)
- Terminal-style welcome when a chat has no messages: `interless ›` + blinking caret, model-status
  line, four context-aware starter prompts (chat vs. code mode), and keyboard hints.

### 4. Layout persistence + resizable sidebar (`WorkspaceView`, `AppControls`)
- `ResizableDivider` drags the sidebar (200–420px), uses `.global` coordinate space (fixes the jitter).
- Sidebar width, sidebar visibility, and inspector visibility persist across launches (`@AppStorage`).

### 5. Personalization (`SettingsHubView`, `InterlessApp`, `DesignTokens`)
- Working System / Light / Dark theme control, persisted, applied at app root via `.preferredColorScheme`.

### 6. Typography — Dynamic Type + consistent ramp (`DesignTokens`, `ChatPaneView`)
- Tokens anchored to system text styles so they scale: title 22 → title2 17 → title3 15 → body 13
  → body-mono 13 → subheadline-mono 11 → footnote-mono 10. Strictly descending hierarchy.
- Composer's hardcoded 10pt labels routed to `metaMonoSm`.

### 7. Accessibility
- `SegmentedToggle` rebuilt as real Buttons (keyboard + VoiceOver, `.isSelected` trait).
- File-tree rows: `.isButton` trait + `accessibilityAction` (keyboard-activatable).
- Active-now dot labeled; decorative chevrons/arrows hidden from VoiceOver.
- Contrast fixes verified ≥4.5:1 (small text) / ≥3:1 (graphics).

### 8. Settings cleanup (`SettingsHubView`, `WorkspaceView`)
- "Show reasoning traces" + "Wide chat layout" wired live (shared `@AppStorage`), persisted.
- Removed three placeholder toggles with no backing behavior (sticky header, Bash/Edit expand defaults).

### 9. Consolidation
- Removed dead `conversationIdentity` view; swept ~20 magic spacing/radius numbers onto tokens;
  reconciled the divergent `PromptComposerView` onto the token system.

---

## QA checklist

### Build
- [ ] `swift build` (or Xcode build) succeeds. Paste any error back to Claude.

### Visual — dark mode (hero)
- [ ] Amber accents on send/focus/selection; phosphor only on agent badge, active dot, streaming, caret.
- [ ] No black halos around the top-bar title; vignette reads as depth, not grime.
- [ ] Empty state renders centered with blinking caret + starter cards.
- [ ] Type hierarchy reads cleanly (headers > titles > body > meta).

### Visual — light mode
- [ ] Top bar uses a clean cream scrim (no black text halo).
- [ ] Tertiary text legible; borders visible.

### Motion
- [ ] Streaming shows pulsing "generating" + blinking caret; active-now dot pulses.
- [ ] System Settings → Accessibility → Display → **Reduce Motion ON** → animations go static (no looping).

### Layout persistence
- [ ] Drag sidebar — smooth, no jitter, clamps 200–420px, resize cursor shows.
- [ ] Toggle sidebar (⌃⌘S) and inspector; quit and relaunch → widths/visibility restored.

### Personalization
- [ ] Settings → Appearance → Theme: System/Light/Dark switches the whole window; persists across relaunch.

### Dynamic Type
- [ ] Bump system text size → app text scales and hierarchy holds; layouts don't break at 200%.

### Settings wiring
- [ ] "Show reasoning traces" toggles the reasoning label on assistant messages (live).
- [ ] "Wide chat layout" widens the conversation column (live). Both persist across relaunch.
- [ ] No permanently-disabled/greyed toggles remain.

### Accessibility — needs real assistive tech (the two I can't verify in code)
- [ ] **Full Keyboard Access ON**: Tab reaches the segmented controls and file-tree rows;
      every focused control shows a visible focus ring.
- [ ] **VoiceOver**: logical reading order through the custom top bar; focus moves *into*
      the Settings/Health overlay panels when opened (they're not real sheets).
      If focus doesn't enter, Claude will add `.accessibilityAddTraits(.isModal)` / focus management.

---

## Parked (deliberate scope decisions)
- Chat render mode / user-message rendering / diff-layout selectors in Settings are read-only and
  currently unconsumed — implementing them is a feature task (chat/diff rendering), not a settings fix.
- Runtime accent-direction and density personalization intentionally not added (would dilute brand coherence / need a token refactor).
- 8pt label in the dense token-budget stepper left fixed (deliberate micro-control exception).
