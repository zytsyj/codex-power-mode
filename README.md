# Codex Power Mode

An agent activity feedback layer designed for Codex. Power Mode turns observing, acting, verifying, waiting, recovering, and completing into legible visual states—without pretending Codex is typing at a keyboard.

> Private incubation project. The repository is intentionally not open source yet.

## Current v0.6.23

- Maps Codex lifecycle activity into six semantic states: Observe, Act, Verify, Wait, Recover, and Complete.
- Uses Momentum for useful steps, Confidence for verification evidence, and Risk for change scope.
- Adds a separate short-lived Combo link for consecutive Codex steps; it never replaces Momentum.
- Gives small and large edits equal Momentum; larger changes increase Risk instead.
- Surfaces permission requests as an explicit attention state.
- Measures added and removed lines without storing source code in the HUD event stream.
- Recognizes common test, build, lint, and type-check commands.
- Requires successful post-edit verification for an evidence-backed completion.
- Gives verified, unverified, cancelled, and no-change endings distinct motion rhythms; Focus confirms quietly while Arcade reserves multi-stage impact for evidence-backed success.
- Streams events to a compact zero-dependency floating HUD with agent state, confidence, evidence, and risk signals.
- Includes a native macOS transparent, click-through overlay anchored to the Codex window, with an optional global visibility mode.
- Includes semantic demo and recent-event replay tools for visual tuning.
- Holds the final result, lets Combo drain and disconnect, then settles into a neutral Idle state while visible energy returns to zero.
- Drops static Idle, orb, and always-expanded HUDs to a one-second heartbeat; active particles, fades, positioning, and Combo decay still use the responsive render path.
- Keeps reduced-motion feedback semantic: events briefly show a fixed, phase-colored confirmation ring and compact glyph instead of particles, rotation, shaking, or full-screen flashes.
- Auto-hides after settling or keeps a quiet `0 / Idle` orb, while Wait, Recover, and reconnect states remain visible.
- Supports restrained `focus` and high-energy `arcade` effect presets.
- Adds a lightweight macOS menu-bar control for language, effects, idle behavior, size, motion, and drag positioning.

## Try it locally

Requires Node.js 20 or newer.

```bash
npm start
npm run demo
npm run showcase
npm run replay
```

The HUD runs on `http://127.0.0.1:4737` and binds only to localhost.
Use `npm run showcase` to play every semantic state with enough delay to compare their motion language. Demo, showcase, and replay are transient previews: they never change the connected task, energy, Combo, event history, or personal best, and the real HUD state is restored when playback ends.

For the native macOS overlay:

```bash
npm run native
npm run demo
npm run status
npm run native:stop
```

The native executable is compiled locally with the installed Swift toolchain and cached under the ignored `.power-mode/` directory. It follows the foremost Codex window and does not modify or inject code into the Codex app. When **Show while Codex is inactive** is enabled, it re-anchors to the current foreground window and remains globally visible above other apps, including across displays and Stage Manager groups.

On macOS, the Codex `SessionStart` hook automatically ensures both the event service and native overlay are running. Existing processes are reused, so opening another session does not create duplicate overlays.

`UserPromptSubmit` moves the HUD into Observe immediately after a message is sent, with “Understanding your request” feedback before the first tool call. Power Mode records the lifecycle transition but never stores the prompt text.

`npm run status` reports service health, the native overlay PID and launch configuration, the current semantic state, and how many demo versus real Codex lifecycle events the running service has received. If `realEventsReceived` remains `0` after Codex uses a tool, review and trust the plugin hooks in Codex.

The macOS menu-bar bolt is the settings entry point. Power Mode only tracks conversations opened in the Codex desktop app; CLI and subagent activity is ignored. **Activity source** can protect the current app conversation from concurrent activity or follow the latest activity across all Codex app conversations. **Effect intensity** independently controls particle density and impact without changing the Focus/Arcade rhythm, and **Show Combo** can remove the Combo bar without spending high-frequency redraws on its hidden decay. The menu shows the source currently in use plus a compact identifier for the session driving the HUD. Choose **Adjust position…** (or press `⌥⌘P`), drag the HUD inside the Codex window, and release to lock it back into click-through mode. The menu also reports historical best energy and Combo. Settings are saved immediately in the versioned `overlay-config.json`, survive overlay restarts, and pre-schema development settings are intentionally reset rather than migrated.

Optional environment variables:

- `CODEX_POWER_MODE_EDGE`: `top-right` (default), `top-left`, `bottom-right`, `bottom-left`, or `center`.
- `CODEX_POWER_MODE_REDUCED_MOTION=1`: update the HUD without particles, flashes, or spatial motion while preserving distinct static state markers.
- `CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE=1`: keep the overlay visible while Codex is behind another app.
- `CODEX_POWER_MODE_PRESET=arcade`: increase particle density, replay cadence, and finisher intensity. The default is `focus`.
- `CODEX_POWER_MODE_INTENSITY=low|normal|high`: tune effect density independently of the semantic preset.
- `CODEX_POWER_MODE_SHOW_COMBO=0`: hide the Combo bar and its decay animation.
- `CODEX_POWER_MODE_SCALE`: scale the floating HUD from `0.75` to `1.6`. The default is `1.15` (about 94pt collapsed).
  The HUD automatically scales down when needed to stay inside narrow Codex windows.
- `CODEX_POWER_MODE_IDLE`: `hide` (default), `orb`, or `always`.
- `CODEX_POWER_MODE_LANGUAGE`: `auto` (default), `zh-CN`, or `en`.
- `CODEX_POWER_MODE_ACTIVITY_SOURCE`: `focused` (default) or `global`.
- `CODEX_POWER_MODE_ENABLED=0`: disable drawing while keeping the local service available.
- `CODEX_POWER_MODE_OBSERVE_THROTTLE_MS`: minimum interval between identical Observe animations. Defaults to `900`; set to `0` to disable coalescing.
- `CODEX_POWER_MODE_PORT`: local event-service port used consistently by the server, hooks, browser HUD, and native overlay. Defaults to `4737`.
- `CODEX_POWER_MODE_AUTO_NATIVE=0`: keep automatic session startup limited to the event service instead of launching the macOS overlay.

Manual runs store state under `~/.codex/power-mode` by default so runtime history is never bundled into the plugin source. Installed hooks continue to use the Codex-provided `PLUGIN_DATA` directory.

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
- An expired link starts again at `1×` with a brief `RELINK` / `重连` bridge; a new turn or Codex session also starts at `1×` but is deliberately not presented as a continuation.
- Active Combo uses a dedicated high-contrast bar below the orb; its critical cadence accelerates near expiry, then the rail visibly splits and flashes `LOST` / `断连` once after a break.

## Roadmap

- Focus, Arcade, Review, and Accessible visual presets.
- More granular tool-family feedback and long-running task milestones.
- Multi-task and subagent presence.
- Native overlays for Windows and Linux.
- Optional sound and richer accessibility controls.
- Signed releases and public-source readiness review.
