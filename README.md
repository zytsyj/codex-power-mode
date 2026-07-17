# Codex Power Mode

Reactive visual effects for Codex edits and verification. Every supported code patch builds a combo, tests and builds charge Power Mode, failures trigger Danger mode, and only verified work earns a Victory finish.

> Private incubation project. The repository is intentionally not open source yet.

## Current MVP

- Captures Codex `apply_patch` activity through plugin hooks.
- Measures added and removed lines without storing source code in the HUD event stream.
- Recognizes common test, build, lint, and type-check commands.
- Maintains combo, score, best combo, and verification state locally.
- Streams events to a zero-dependency browser HUD with particle effects.
- Requires a successful post-edit verification before showing Victory.

## Try it locally

Requires Node.js 20 or newer.

```bash
npm start
npm run demo
```

The HUD runs on `http://127.0.0.1:4737` and binds only to localhost.

## Plugin layout

```text
.codex-plugin/plugin.json   Plugin metadata
hooks/hooks.json            Codex lifecycle hook declarations
hooks/*.mjs                 Session and tool event handlers
skills/power-mode/          User-facing Power Mode workflow
src/                        Event parsing, scoring, and persistence
overlay/                    Real-time visual HUD
scripts/                    Server and control command
test/                       Node test suite
```

Installed plugin hooks must be reviewed and trusted by the user before Codex runs them. Power Mode hooks are observational: they do not block or rewrite tool calls.

## Privacy and safety

- All state stays on the local machine.
- The HUD listens on `127.0.0.1` only.
- Patch source text is reduced to line and character counts before persistence.
- Hook failures never block Codex work.
- There are no runtime dependencies or analytics.

## Roadmap

- Native transparent, click-through desktop overlay.
- Per-language particle palettes and richer diff classification.
- VS Code bridge for effects positioned on exact edited lines.
- Configurable presets, reduced-motion mode, sound, and accessibility controls.
- Signed releases and public-source readiness review.
