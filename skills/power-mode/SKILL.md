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

To replay up to 40 recent locally stored events without changing state:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" replay
```

## Show status

Run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" status
```

Summarize phase, momentum, confidence, risk, edited lines, and verification evidence. Call a completion verified only when `completion` is `verified`. If the service is running but `service.activity.realEventsReceived` stays at `0` after a tool call, explain that the Power Mode hooks still need to be reviewed and trusted in Codex.

## Behavior

- `PreToolUse` maps Codex activity into observe, act, and verify phases.
- Permission requests enter a visible wait state that asks for user attention.
- Each useful edit step adds the same momentum; large diffs raise risk instead of earning a larger reward.
- Successful tests, builds, lint, or type checks add confidence and evidence.
- Failed verification enters recovery and lowers confidence.
- A turn gets an evidence-backed completion only when the latest edit is followed by successful verification.
- Do not run extra commands solely to increase momentum or confidence.
