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

On macOS, settings live under the menu-bar bolt. It controls Focus/Arcade, the bounded 0.55×/0.72×/0.90×/1.10× Energy gain multiplier, independent low/normal/high effect intensity, agent Combo visibility, opt-in Typing Combo, cursor effects (Off/Sparks/Neon), auto-hide versus a quiet Idle orb, the immediate/2-second/6-second auto-hide delay, English/Chinese, size, reduced motion, inactive-Codex behavior, activity source, and drag positioning. Energy gain changes are read from the shared settings file on the next real event and need no restart; they do not bypass the evidence gate for verified Peak. Typing Combo requires macOS Accessibility permission, listens only while Codex is the foreground app, ignores deletion/control/navigation keys, and keeps only a capped rhythm count and timestamp—never text or key values. Its large `×N` counter is separate from the orb; cursor particles are separately configurable, and submit streams the counter into the orb. Activity source offers Focus (keep one conversation), Global (follow the latest conversation with isolated state), and Mix (share one Energy/Combo pool for all Codex app conversations). Every Mix conversation end receives a brief completion result stamp without resetting the shared pool; the final conversation receives the full Complete family. The hide delay begins only after completion feedback, Combo, and energy return have settled; it does not extend an active Combo. The inactive behavior can hide the HUD, keep it over the last Codex window position, or follow the current foreground app. Hiding Combo also disables its otherwise invisible high-frequency decay redraw. Positioning mode temporarily makes only the HUD hit target interactive; releasing the drag restores click-through behavior. Settings survive overlay restarts, and the menu reports historical best energy and Combo.

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

To compare all seven Energy tiers in order without altering real state, run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" energy-showcase
```

To compare the shared Complete closure followed by the four result stamps, run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" completion-showcase
```

Demo, showcase, Energy showcase, completion showcase, and replay are transient previews. They do not change the connected task, energy, Combo, history, or personal best, and restore the real HUD state after playback.

To replay up to 40 recent locally stored events without changing state:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" replay
```

## Show status

Run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" status
```

Read `hudDisplay` as the state currently visible after settling and decay, and `taskState` as the last raw task state. Summarize phase, energy level, Combo stage, momentum, confidence, risk, edited lines, and verification evidence. Call a completion verified only when `taskState.completion` is `verified`. If the service is running but `service.activity.realEventsReceived` stays at `0` after a tool call, explain that the Power Mode hooks still need to be reviewed and trusted in Codex.

## Behavior

- `UserPromptSubmit` immediately enters Observe with “Understanding your request”; prompt text is never persisted.
- `PreToolUse` maps Codex activity into observe, act, and verify phases.
- Permission requests enter a visible wait state that asks for user attention.
- Each useful edit step adds the same momentum; large diffs raise risk instead of earning a larger reward.
- Energy spans `0–999`: Wake, Charge, Drive, High, Overload, Critical, and an evidence-backed verified Peak. The visible ring fills within each tier and resets after a breakthrough; decay drains to a boundary, morphs the orb backward, then resumes from a full lower-tier ring. Evolution is cumulative and deliberately paced: Wake awakens a breathing core, Charge adds three collector nodes, Drive adds directional propulsion arcs, High crystallizes an internal lattice, Overload opens energy vents, Critical links the collectors with magnetic bridges, and Peak synchronizes every retained system beneath a white-gold crown. Downgrades remove those abilities in reverse order.
- Typing Combo is separate from agent Combo. A real `UserPromptSubmit` consumes a recent input rhythm into a bounded Energy injection scaled by the selected Energy gain multiplier; input alone cannot reach the verified Peak.
- Combo progresses through Ignite, Link, Accel, Heat, and Extreme. Every increase pulses, tier crossings expand, the critical window double-warns, and expiry fractures the outer ring. Its normal drain window is 14 seconds.
- Successful tests, builds, lint, or type checks add confidence and evidence and briefly lock the Combo in a Boost reward window.
- Failed verification enters recovery and lowers confidence.
- A turn gets an evidence-backed completion only when the latest edit is followed by successful verification.
- Every Complete outcome begins with the same stop, closed-ring, and Complete stamp. Its second beat adds the result: verified celebrates with three reward rings, unverified leaves a caution gap, cancelled retracts two split arcs, and no-change settles a thin cyan ring. All four then share the same smooth return to zero.
- Focus uses restrained single-beat state motion; Arcade uses faster multi-stage capture, drive, and verification rhythms rather than only adding particles.
- Long Wait and Recover states automatically settle into slower, lower-amplitude motion while keeping their meaning visible.
- The static Idle orb uses a one-second heartbeat without redrawing identical frames. The browser presentation timer stops entirely after a settled auto-hide, while new activity, disconnects, and reconnects wake it immediately; active effects and Combo decay still render responsively.
- Reduced motion keeps fixed phase geometry and adds a short, non-animated confirmation ring and glyph for Observe, Act, Verify, Wait, Recover, and completion outcomes.
- Recovery failures return to Idle after a short repair window when Codex emits no follow-up event; permission waits remain visible until the user acts.
- A terminal result holds briefly, Combo drains and disconnects, then the HUD enters Idle while visible energy eases to zero over roughly 45 seconds. Historical best values remain available in the menu.
- Do not run extra commands solely to increase momentum or confidence.
