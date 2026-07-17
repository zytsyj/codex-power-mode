---
name: power-mode
description: Start, inspect, or demonstrate Codex Power Mode. Use when the user asks to enable Power Mode, see the combo HUD, run the effect demo, or inspect Power Mode status.
---

# Codex Power Mode

Use the bundled control script through `${PLUGIN_ROOT}/scripts/power-mode.mjs`.

## Start the HUD

Run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" start --open
```

Tell the user the HUD is running at `http://127.0.0.1:4737`. The plugin hooks automatically capture supported Codex edits and verification commands after the user has reviewed and trusted them.

## Demo the effects

Make sure the HUD is open, then run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" demo
```

## Show status

Run:

```bash
node "${PLUGIN_ROOT}/scripts/power-mode.mjs" status
```

Summarize combo, best combo, score, edited lines, and verification count. Do not claim victory unless the stored mode is `victory`.

## Behavior

- File additions and removals build combo through `PostToolUse` hooks.
- Successful tests, builds, lint, or type checks add verification bonuses.
- A failed verification resets the current combo and activates Danger mode.
- A turn ends in Victory only when the latest edit is followed by a successful verification.
- Do not run extra commands solely to farm combo points.
