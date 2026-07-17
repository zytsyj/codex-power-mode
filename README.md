# Codex Power Mode

Reactive visual effects for Codex edits and verification. Every supported code patch builds a combo, tests and builds charge Power Mode, failures trigger Danger mode, and only verified work earns a Victory finish.

> Private incubation project. The repository is intentionally not open source yet.

## Current MVP

- Captures Codex `apply_patch` activity through plugin hooks.
- Measures added and removed lines without storing source code in the HUD event stream.
- Recognizes common test, build, lint, and type-check commands.
- Maintains combo, score, best combo, and verification state locally.
- Streams events to a zero-dependency browser HUD with particle effects.
- Includes a native macOS transparent, click-through overlay constrained to the Codex window.
- Replays large patches as rapid virtual typing bursts with sparks, shockwaves, and combo shake.
- Requires a successful post-edit verification before showing Victory.

## Try it locally

Requires Node.js 20 or newer.

```bash
npm start
npm run demo
```

The HUD runs on `http://127.0.0.1:4737` and binds only to localhost.

For the native macOS overlay:

```bash
npm run native
npm run demo
npm run native:stop
```

The native executable is compiled locally with the installed Swift toolchain and cached under the ignored `.power-mode/` directory. It follows the active Codex window, hides when Codex is not in front, and does not modify or inject code into the Codex app.

Optional environment variables:

- `CODEX_POWER_MODE_EDGE`: `top-right` (default), `top-left`, `bottom-right`, `bottom-left`, or `center`.
- `CODEX_POWER_MODE_REDUCED_MOTION=1`: update the HUD without particles or flashes.
- `CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE=1`: keep the overlay visible while Codex is behind another app.

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

- Native overlays for Windows and Linux.
- Per-language particle palettes and richer diff classification.
- Configurable presets, reduced-motion mode, sound, and accessibility controls.
- Signed releases and public-source readiness review.
