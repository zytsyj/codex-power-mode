# Architecture

Codex Power Mode is a local feedback system for the Codex desktop app. It does not inject code into Codex and does not bridge to VS Code or the Codex CLI.

## Data flow

1. Codex plugin hooks reduce lifecycle activity to small semantic events such as Observe, Act, Verify, Wait, Recover, and Complete.
2. The local Node.js service validates, authenticates, reduces, and persists those events per desktop conversation.
3. The native macOS overlay subscribes to the authenticated loopback event stream and renders a transparent, click-through HUD with Core Animation.
4. Optional Typing Combo uses a listen-only macOS event tap for rhythm and Accessibility APIs for the current insertion-point bounds. It never receives character values from the event tap.

## Components

- `hooks/`: trusted Codex lifecycle adapters. Failures never block Codex work.
- `src/`: validation, state reduction, session arbitration, storage, authentication, diagnostics, and maintenance boundaries.
- `scripts/server.mjs`: loopback-only authenticated event and HUD service.
- `scripts/power-mode.mjs`: start, stop, demo, status, health, and guarded maintenance commands.
- `native/macos/PowerModeOverlay.swift`: transparent macOS HUD, menu settings, input rhythm monitoring, cursor effects, and native diagnostics.
- `overlay/`: browser fallback and development preview.

## State ownership

Focus isolates one task, Global follows the latest desktop task while retaining separate state, and Mix combines desktop tasks into a shared pool. CLI and subagent activity are rejected before state ownership. Prompt text, source text, key values, and command bodies are not part of the state model.

## Runtime boundaries

The service binds to `127.0.0.1`, uses a per-installation token stored with owner-only permissions, and rejects unauthenticated, cross-origin, oversized, malformed, or sensitive payloads. Runtime data lives outside the plugin package so upgrades can replace cached plugin versions without losing settings.

## Rendering

The HUD uses compositor-backed layers rather than repainting the full Codex window every frame. Energy material, semantic state, agent Combo, Typing Combo, and transient effects have separate layers and bounded effect counts. Hidden and settled states reduce or suspend refresh work.
