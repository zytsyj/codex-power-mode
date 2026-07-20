# Codex Power Mode

An agent activity feedback layer designed for Codex. Power Mode turns observing, acting, verifying, waiting, recovering, and completing into legible visual states—without pretending Codex is typing at a keyboard.

> Private incubation project. The repository is intentionally not open source yet.

## Current v0.6.12

- Maps Codex lifecycle activity into six semantic states: Observe, Act, Verify, Wait, Recover, and Complete.
- Uses Momentum for useful steps, Confidence for verification evidence, and Risk for change scope.
- Adds a separate short-lived Combo link for consecutive Codex steps; it never replaces Momentum.
- Gives small and large edits equal Momentum; larger changes increase Risk instead.
- Surfaces permission requests as an explicit attention state.
- Measures added and removed lines without storing source code in the HUD event stream.
- Recognizes common test, build, lint, and type-check commands.
- Requires successful post-edit verification for an evidence-backed completion.
- Streams events to a compact zero-dependency floating HUD with agent state, confidence, evidence, and risk signals.
- Includes a native macOS transparent, click-through overlay constrained to the Codex window.
- Includes semantic demo and recent-event replay tools for visual tuning.
- Auto-collapses to a small transparent Momentum orb between events.
- Supports restrained `focus` and high-energy `arcade` effect presets.

## Try it locally

Requires Node.js 20 or newer.

```bash
npm start
npm run demo
npm run showcase
npm run replay
```

The HUD runs on `http://127.0.0.1:4737` and binds only to localhost.
Use `npm run showcase` to play every semantic state with enough delay to compare their motion language.

For the native macOS overlay:

```bash
npm run native
npm run demo
npm run native:stop
```

The native executable is compiled locally with the installed Swift toolchain and cached under the ignored `.power-mode/` directory. It follows the foremost Codex window, hides when Codex is not in front, and does not modify or inject code into the Codex app.

On macOS, the Codex `SessionStart` hook automatically ensures both the event service and native overlay are running. Existing processes are reused, so opening another session does not create duplicate overlays.

Optional environment variables:

- `CODEX_POWER_MODE_EDGE`: `top-right` (default), `top-left`, `bottom-right`, `bottom-left`, or `center`.
- `CODEX_POWER_MODE_REDUCED_MOTION=1`: update the HUD without particles or flashes.
- `CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE=1`: keep the overlay visible while Codex is behind another app.
- `CODEX_POWER_MODE_PRESET=arcade`: increase particle density, replay cadence, and finisher intensity. The default is `focus`.
- `CODEX_POWER_MODE_SCALE`: scale the floating HUD from `0.75` to `1.6`. The default is `1.15` (about 94pt collapsed).
  The HUD automatically scales down when needed to stay inside narrow Codex windows.
- `CODEX_POWER_MODE_OBSERVE_THROTTLE_MS`: minimum interval between identical Observe animations. Defaults to `900`; set to `0` to disable coalescing.
- `CODEX_POWER_MODE_AUTO_NATIVE=0`: keep automatic session startup limited to the event service instead of launching the macOS overlay.

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
- Patch source text is reduced to line and character counts before persistence; command contents are not stored.
- Hook failures never block Codex work.
- There are no runtime dependencies or analytics.
- Focus and Arcade enforce separate particle, shockwave, and scan budgets so bursts cannot accumulate without bound during rapid tool activity.
- Repeated identical read/search activity is throttled, while Act, Verify, Wait, Recover, and Complete events are never hidden by that throttle.

## Combo semantics

- A new Codex tool step starts or extends Combo; edits add one link and successful verification adds two.
- Observe begins draining immediately. Act gets a 15-second tool hold, Verify gets a 90-second hold, then the bar drains over 12 seconds.
- Permission waits preserve Combo for 15 seconds before draining, so approval latency is not treated as an instant failure.
- Failed verification and unverified completion break Combo immediately.
- An expired link, a new turn, or a new Codex session starts again at `1×`; Combo cannot increase forever across unrelated work.

## Roadmap

- Focus, Arcade, Review, and Accessible visual presets.
- More granular tool-family feedback and long-running task milestones.
- Multi-task and subagent presence.
- Native overlays for Windows and Linux.
- Optional sound and richer accessibility controls.
- Signed releases and public-source readiness review.
