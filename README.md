# Codex Power Mode

An agent activity feedback layer designed for Codex. Power Mode turns observing, acting, verifying, waiting, recovering, and completing into legible visual states—without pretending Codex is typing at a keyboard.

> Private incubation project. The repository is intentionally not open source yet.

## Current v0.8.0 private stable

- Maps Codex lifecycle activity into six semantic states: Observe, Act, Verify, Wait, Recover, and Complete.
- Uses a `0–999` Energy scale for useful progress, Confidence for verification evidence, and Risk for change scope; only evidence-backed completion reaches the verified peak.
- Adds a separate short-lived Combo link for consecutive Codex steps; it never replaces Momentum.
- Gives every Combo increase a visible pulse, expands through five count tiers, warns with a double beat near expiry, and fractures explicitly on disconnect.
- Supports Focus (hold the current conversation), Global (follow the latest conversation with isolated state), and Mix (one shared Energy/Combo pool for all Codex app conversations).
- Decays inactive conversations by real elapsed time before they return to the HUD, then uses a compositor handoff instead of abruptly swapping stale energy values.
- Gives small and large edits equal Momentum; larger changes increase Risk instead.
- Surfaces permission requests as an explicit attention state.
- Measures added and removed lines without storing source code in the HUD event stream.
- Recognizes common test, build, lint, and type-check commands.
- Requires successful post-edit verification for an evidence-backed completion.
- Gives verified, unverified, cancelled, and no-change endings distinct motion rhythms; Focus confirms quietly while Arcade reserves multi-stage impact for evidence-backed success.
- Keeps Act directional with a thrust axis and makes Verify converge through four lock brackets, including static silhouettes when Reduced Motion is enabled.
- Streams events to a compact zero-dependency floating HUD with agent state, confidence, evidence, and risk signals.
- Includes a native macOS transparent, click-through overlay anchored to the Codex window, with an optional global visibility mode.
- Includes semantic demo and recent-event replay tools for visual tuning.
- Holds the final result, lets Combo drain and disconnect, then settles into a neutral Idle state while visible energy returns to zero.
- Drops the static Idle orb to a one-second heartbeat, and suspends the browser presentation timer entirely after auto-hide; new activity or connection changes wake it immediately.
- Keeps reduced-motion feedback semantic: events briefly show a fixed, phase-colored confirmation ring and compact glyph instead of particles, rotation, shaking, or full-screen flashes.
- Auto-hides after settling or keeps a quiet `0 / Idle` orb, while Wait, Recover, and reconnect states remain visible.
- Supports restrained `focus` and high-energy `arcade` effect presets.
- Adds a lightweight macOS menu-bar control for language, effects, idle behavior and its hide delay, size, motion, and drag positioning.
- Keeps saved and preset positions inside the active display's visible area and recovers them after resolution, Dock, or monitor-layout changes.

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

The native executable is compiled locally with the installed Swift toolchain and cached under the ignored `.power-mode/` directory. It follows the foremost Codex window and does not modify or inject code into the Codex app. **When Codex is inactive** offers three explicit policies: hide the HUD, keep it over the last Codex window position, or re-anchor it to the current foreground app. The two visible policies remain above other apps across displays and Stage Manager groups.

On macOS, the Codex `SessionStart` hook automatically ensures both the event service and native overlay are running. Existing processes are reused, so opening another session does not create duplicate overlays.

`UserPromptSubmit` moves the HUD into Observe immediately after a message is sent, with “Understanding your request” feedback before the first tool call. Power Mode records the lifecycle transition but never stores the prompt text.

`npm run status` reports service health, the native overlay PID and launch configuration, `hudDisplay` for the state currently shown after settling/decay, `taskState` for the last raw task state, and how many demo versus real Codex lifecycle events the running service has received. If `realEventsReceived` remains `0` after Codex uses a tool, review and trust the plugin hooks in Codex.

The macOS menu-bar bolt is the settings entry point. Power Mode only tracks conversations opened in the Codex desktop app; CLI and subagent activity is ignored. **Status & connection** separates the current HUD display from the raw task state and lists the last real event, task origin, following policy, connection health, and full session identity. **Activity source** offers Focus, Global, and Mix: Focus protects the current conversation, Global follows the latest conversation while keeping each score isolated, and Mix combines every Codex app conversation into one shared Energy and Combo pool. **Effect intensity** independently controls particle density and impact without changing the Focus/Arcade rhythm, and **Show Combo** can remove the Combo ring without spending high-frequency redraws on its hidden decay. **Idle behavior** can keep a quiet orb or hide the HUD; when hiding is selected, **Auto-hide delay** chooses whether it disappears immediately or leaves the settled Idle orb visible for 2 or 6 seconds. **When Codex is inactive** separately controls whether the HUD hides, stays at the last Codex anchor, or follows the active app. Choose **Adjust position…** (or press `⌥⌘P`), drag the HUD inside the Codex window, and release to lock it back into click-through mode. The menu also reports historical best energy and Combo. Settings are saved immediately in the versioned `overlay-config.json` and survive overlay restarts.

Optional environment variables:

- `CODEX_POWER_MODE_EDGE`: `top-right` (default), `top-left`, `bottom-right`, `bottom-left`, or `center`.
- `CODEX_POWER_MODE_REDUCED_MOTION=1`: update the HUD without particles, flashes, or spatial motion while preserving distinct static state markers.
- `CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE=1`: keep the overlay visible while Codex is behind another app.
- `CODEX_POWER_MODE_PRESET=arcade`: increase particle density, replay cadence, and finisher intensity. The default is `focus`.
- `CODEX_POWER_MODE_INTENSITY=low|normal|high`: tune effect density independently of the semantic preset.
- `CODEX_POWER_MODE_SHOW_COMBO=0`: hide the Combo bar and its decay animation.
- `CODEX_POWER_MODE_SCALE`: scale the floating HUD from `0.75` to `1.6`. The default is `1.15` (about 94pt collapsed).
  The HUD automatically scales down when needed to stay inside narrow Codex windows.
- `CODEX_POWER_MODE_IDLE`: `hide` (default) or `orb`.
- `CODEX_POWER_MODE_LANGUAGE`: `auto` (default), `zh-CN`, or `en`.
- `CODEX_POWER_MODE_ACTIVITY_SOURCE`: `focused` (default), `global`, or `mix`.
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
- Each installation creates a private `0600` service token. Hooks, diagnostics, and the native HUD authenticate every API and event-stream request.
- The browser HUD receives a separate process-scoped, stream-only token through a same-origin bootstrap; cross-origin pages cannot subscribe to HUD state or post events.
- Patch source text is reduced to line and character counts before persistence; command contents are not stored.
- The local service rejects malformed lifecycle events, sensitive prompt/command fields, oversized payloads, and invalid JSON without interrupting Codex work.
- Hook failures never block Codex work.
- There are no runtime dependencies or analytics.
- Focus and Arcade enforce separate particle, shockwave, and scan budgets so bursts cannot accumulate without bound during rapid tool activity.
- Energy spans Wake, Charge, Drive, High, Overload, Critical, and the verified `999` Peak. Every crossover changes ring weight and glow and fires a one-shot breakthrough or vent animation.
- Repeated identical read/search activity is throttled, while Act, Verify, Wait, Recover, and Complete events are never hidden by that throttle.

## Combo semantics

- A new Codex tool step starts or extends Combo; edits add one link and successful verification adds two. Every increase pulses the ring, while tier crossings create a larger expansion.
- Observe begins draining immediately. Act gets a 15-second tool hold, Verify gets a 90-second hold, then the bar drains over 12 seconds.
- Permission waits preserve Combo for 15 seconds before draining, so approval latency is not treated as an instant failure.
- Failed verification and unverified completion break Combo immediately.
- An expired link starts again at `1×` with a brief `RELINK` / `重连` bridge; a new turn or Codex session also starts at `1×` but is deliberately not presented as a continuation.
- Combo progresses through Ignite (`1–4×`), Link (`5–9×`), Accel (`10–19×`), Heat (`20–39×`), and Extreme (`40×+`). Its critical cadence emits a double warning near expiry, then the outer ring visibly fractures once after a break.
- Passing checks use three reward tiers: restrained confirmation without a recent edit, green Boost when evidence backs the latest change, and a gold Record beat when that evidence also sets a personal best.

## Roadmap

- Focus, Arcade, Review, and Accessible visual presets.
- More granular tool-family feedback and long-running task milestones.
- Multi-task and subagent presence.
- Native overlays for Windows and Linux.
- Optional sound and richer accessibility controls.
- Signed releases and public-source readiness review.
