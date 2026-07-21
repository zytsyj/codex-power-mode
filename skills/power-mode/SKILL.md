---
name: power-mode
description: Start, inspect, replay, or demonstrate Codex Power Mode. Use when the user asks to enable Power Mode, see the semantic agent-state HUD, run the effect demo, replay recent activity, or inspect momentum and verification status.
---

# Codex Power Mode

Use the bundled control script through `${PLUGIN_ROOT}/scripts/power-mode.mjs`.

## Start the HUD

On macOS, prefer the native transparent overlay:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" native
```

On other platforms, or when the user explicitly requests the browser HUD, run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" start --open
```

Tell the user the HUD is running at `http://127.0.0.1:4737`. The plugin hooks automatically capture supported Codex edits and verification commands after the user has reviewed and trusted them.

On macOS, settings live under the menu-bar bolt. It controls Focus/Arcade, independent low/normal/high effect intensity, Combo visibility, auto-hide versus a quiet Idle orb, English/Chinese, size, reduced motion, global inactive-window visibility, and drag positioning. Hiding Combo also disables its otherwise invisible high-frequency decay redraw. Positioning mode temporarily makes only the HUD hit target interactive; releasing the drag restores click-through behavior. Settings survive overlay restarts, and the menu reports historical best energy and Combo.

Positioning mode keeps the full HUD inside the Codex window, snaps near edges, shows the active snap direction, and reports the saved region in the menu. Position presets include Smart, four corners, and center. Smart placement avoids the title bar and reserves space for common Codex side panels on wide windows; a manually dragged position always wins. Reset position exits positioning and returns to Smart placement.

Saved and preset positions are constrained to the active display's visible area. Resolution, Dock, and monitor-layout changes trigger immediate repositioning, so a removed display cannot leave the HUD stranded off-screen.

To stop the native overlay:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" native-stop
```

## Demo the effects

Make sure the HUD is open, then run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" demo
```

To show every semantic state with enough delay for visual comparison, run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" showcase
```

Demo, showcase, and replay are transient previews. They do not change the connected task, energy, Combo, history, or personal best, and restore the real HUD state after playback.

To replay up to 40 recent locally stored events without changing state:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" replay
```

## Show status

Run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" status
```

Summarize phase, energy level, Combo stage, momentum, confidence, risk, edited lines, and verification evidence. Call a completion verified only when `completion` is `verified`. If the service is running but `service.activity.realEventsReceived` stays at `0` after a tool call, explain that the Power Mode hooks still need to be reviewed and trusted in Codex.

## Behavior

- `UserPromptSubmit` immediately enters Observe with “Understanding your request”; prompt text is never persisted.
- `PreToolUse` maps Codex activity into observe, act, and verify phases.
- Permission requests enter a visible wait state that asks for user attention.
- Each useful edit step adds the same momentum; large diffs raise risk instead of earning a larger reward.
- Energy has four visible working levels: Charge, Flow, Surge, and Overdrive.
- Combo progresses through Build, Link, and Chain, then signals a critical break window when little time remains.
- Successful tests, builds, lint, or type checks add confidence and evidence and briefly lock the Combo in a Boost reward window.
- Failed verification enters recovery and lowers confidence.
- A turn gets an evidence-backed completion only when the latest edit is followed by successful verification.
- Complete outcomes stay semantically distinct: verified celebrates, unverified cautions, cancelled interrupts, and no-change settles quietly.
- Focus uses restrained single-beat state motion; Arcade uses faster multi-stage capture, drive, and verification rhythms rather than only adding particles.
- Long Wait and Recover states automatically settle into slower, lower-amplitude motion while keeping their meaning visible.
- Static Idle, orb, and always-expanded HUDs use a one-second heartbeat without redrawing identical frames; active effects and Combo decay still render responsively.
- Reduced motion keeps fixed phase geometry and adds a short, non-animated confirmation ring and glyph for Observe, Act, Verify, Wait, Recover, and completion outcomes.
- Recovery failures return to Idle after a short repair window when Codex emits no follow-up event; permission waits remain visible until the user acts.
- A terminal result holds briefly, Combo drains and disconnects, then the HUD enters Idle while visible energy returns to zero. Historical best values remain available in the menu.
- Do not run extra commands solely to increase momentum or confidence.
