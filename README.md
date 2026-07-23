<div align="center">

<img src="docs/media/arcade-dark-complete.png" width="128" alt="Codex Power Mode completion orb">

# Codex Power Mode

**A semantic activity HUD for Codex.**<br>
See the agent understand, act, verify, wait, recover, and complete—at a glance.

[![macOS](https://img.shields.io/badge/macOS-native-111827?style=flat-square&logo=apple&logoColor=white)](docs/INSTALLATION.md)
[![Node.js 20+](https://img.shields.io/badge/Node.js-20%2B-1f6f4a?style=flat-square&logo=nodedotjs&logoColor=white)](package.json)
[![Runtime dependencies](https://img.shields.io/badge/runtime_deps-0-2563eb?style=flat-square)](docs/DEPENDENCIES.md)
[![Status](https://img.shields.io/badge/status-private_RC-7c3aed?style=flat-square)](docs/RELEASE_CHECKLIST.md)
[![License](https://img.shields.io/badge/license-UNLICENSED-4b5563?style=flat-square)](#known-limitations)

[Install](docs/INSTALLATION.md) · [How it works](docs/ARCHITECTURE.md) · [Privacy](docs/PRIVACY.md) · [FAQ](docs/FAQ.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

</div>

> [!IMPORTANT]
> This is a private incubation project and is intentionally not open source yet. The current build is a private Release Candidate for personal testing, not a public release.

<table>
  <tr>
    <th width="50%">Focus · restrained clarity</th>
    <th width="50%">Arcade · expressive feedback</th>
  </tr>
  <tr>
    <td align="center"><img src="docs/media/focus-demo.gif" width="240" alt="Focus lifecycle: Observe, Act, Verify, Complete"></td>
    <td align="center"><img src="docs/media/arcade-demo.gif" width="240" alt="Arcade lifecycle with Typing Combo, Energy tiers, Verify, and Complete"></td>
  </tr>
</table>

Power Mode reads trusted Codex lifecycle signals—not prompt text, simulated typing, or raw source code—and turns them into a compact visual rhythm. Useful work builds **Energy**, consecutive agent steps maintain **Combo**, verification creates evidence-backed completion, and inactivity settles visibly back to Idle.

## Why Power Mode?

| Semantic, not decorative | Local by design | Calm or expressive |
| --- | --- | --- |
| Six distinct states explain what Codex is doing instead of showing a generic spinner. | The service binds to localhost, uses per-install authentication, and stores no prompt or command text. | Focus keeps motion restrained; Arcade adds stronger impact without changing the underlying state model. |

## One orb, two independent signals

### Agent state

`Observe` → `Act` → `Verify` → `Complete`

Attention paths remain explicit: `Wait` requests input, while `Recover` shows failed work being repaired. Every new event gets one short state-specific action; stable state geometry remains readable after the transient animation leaves.

### Energy evolution

| Energy | Tier | Visual evolution |
| ---: | --- | --- |
| `1–199` | **Wake** | Chassis comes online |
| `200–449` | **Charge** | Three nodes separate and orbit |
| `450–699` | **Drive** | Four-node directional bus engages |
| `700–899` | **Critical** | Six locks and stabilizer assemble |
| `900–999` | **Peak** | The mechanism synchronizes under a white-gold crown |

The ring refills inside each tier, then establishes the next topology. Peak is reached through normal Energy accumulation; verification is not a gate for entering the highest tier.

### Combo

Combo is the short-lived outer arc for consecutive agent steps. It advances through Ignite, Link, Accel, Heat, and Extreme, warns before expiry, and visibly disconnects when the chain breaks. Typing Combo is separate and optional.

## Controls at a glance

| Control | Choices | Purpose |
| --- | --- | --- |
| Visual rhythm | Focus / Arcade | Restrained clarity or high-impact choreography |
| Activity source | Focus / Global / Mix | One task, latest isolated task, or a shared desktop pool |
| Energy gain | 0.30×–1.50× | Tune accumulation without changing tier boundaries |
| Input feedback | Off / Sparks / Neon | Optional cursor feedback and independent Typing Combo |
| Idle behavior | Hide / Quiet orb | Disappear after settling or retain a neutral orb |
| Accessibility | Reduce Motion | Preserve semantic feedback without spatial motion |
| Language | Auto / English / 中文 | Localized HUD labels and controls |

<table>
  <tr>
    <th width="50%">Typing Combo</th>
    <th width="50%">Reduce Motion · Recover</th>
  </tr>
  <tr>
    <td align="center"><img src="docs/media/typing-combo-dark.png" width="220" alt="Gold Typing Combo on a dark background"></td>
    <td align="center"><img src="docs/media/reduced-light-recover.png" width="220" alt="Reduced Motion Recover on a light background"></td>
  </tr>
</table>

## Current scope

- Native transparent, click-through HUD for the Codex desktop app on macOS only.
- Focus, Global, and Mix task-following modes with isolated or shared Energy and Combo.
- Distinct verified, unverified, cancelled, and no-change completion outcomes.
- Fixed semantic confirmations for Reduce Motion.
- Menu-bar controls for language, effects, visibility, size, motion, and positioning.
- Local authenticated event service with zero third-party runtime packages or analytics.
- Reproducible demos, render QA, security, stability, compatibility, and performance checks.

Automated checks are in place, but final publication still depends on hands-on interaction acceptance, a trusted Hook run after installation, Instruments GPU/Energy inspection, compatibility review, and the owner decisions in the [release checklist](docs/RELEASE_CHECKLIST.md).

<details>
<summary><strong>Documentation and release evidence</strong></summary>

<br>

[Installation](docs/INSTALLATION.md) ·
[Architecture](docs/ARCHITECTURE.md) ·
[Privacy](docs/PRIVACY.md) ·
[FAQ](docs/FAQ.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md) ·
[Security audit](docs/SECURITY_AUDIT.md) ·
[Performance](docs/PERFORMANCE.md) ·
[Stability](docs/STABILITY.md) ·
[Compatibility](docs/COMPATIBILITY.md) ·
[Dependencies](docs/DEPENDENCIES.md) ·
[Media provenance](docs/MEDIA.md) ·
[Release archive](docs/RELEASE_ARCHIVE.md) ·
[Security policy](SECURITY.md) ·
[Contributing](CONTRIBUTING.md)

</details>

## Try it locally

Requires Node.js 20 or newer.

```bash
npm start
npm run demo
npm run showcase
npm run showcase:energy
npm run replay
npm run render:demos
npm run render:qa
npm run archive:rc
npm run readiness:rc
npm run security:rc
npm run perf:rc
npm run stability:rc
npm run compatibility:rc
```

The HUD runs on `http://127.0.0.1:4737` and binds only to localhost.
Use `npm run showcase` to compare semantic states, or `npm run showcase:energy` to step through all five Energy tiers. Demo, both showcases, and replay are transient previews: they never change the connected task, energy, Combo, event history, or personal best, and the real HUD state is restored when playback ends.

For the native macOS overlay:

```bash
npm run native
npm run demo
npm run status
npm run doctor
npm run native:stop
```

The native executable is compiled locally with the installed Swift toolchain and cached under the ignored `.power-mode/` directory. It follows the foremost Codex window and does not modify or inject code into the Codex app. **When Codex is inactive** offers three explicit policies: hide the HUD, keep it over the last Codex window position, or re-anchor it to the current foreground app. The two visible policies remain above other apps across displays and Stage Manager groups.

On macOS, the Codex `SessionStart` hook automatically ensures both the event service and native overlay are running. Existing processes are reused, so opening another session does not create duplicate overlays.

`UserPromptSubmit` moves the HUD into Observe immediately after a message is sent, with “Understanding your request” feedback before the first tool call. Power Mode records the lifecycle transition but never stores the prompt text.

`npm run status` reports service health, the native overlay PID and launch configuration, `hudDisplay` for the state currently shown after settling/decay, `taskState` for the last raw task state, and how many demo versus real Codex lifecycle events the running service has received. If `realEventsReceived` remains `0` after Codex uses a tool, review and trust the plugin hooks in Codex.

`npm run doctor` gives a short, non-technical health report for the service, native HUD, installed version, data directory, duplicate processes, event-stream connection, and trusted Codex lifecycle hooks. Use `npm run doctor -- --json` for automation.

`npm run readiness:rc` gives one conservative release-candidate summary. It marks reports from older cachebuster builds as stale and keeps automated checks, a real trusted Hook, hands-on interaction, Instruments review, and owner publication decisions separate. It never changes repository visibility or publishes anything.

## Maintenance and removal

- `npm run stop` safely stops the native HUD and the authenticated local service without deleting settings or history.
- `npm run reset:settings -- --yes` restores display settings and position to defaults, restarts the HUD, and preserves history and personal bests. Without `--yes`, it only explains that confirmation is required.
- `npm run purge:data -- --yes` stops Power Mode and removes its local settings, history, and installation token. It refuses broad or unrecognized directories and does not uninstall the plugin itself.
- Remove the plugin package with `codex plugin remove codex-power-mode@personal`. To remove local data too, run the purge command first.

After an upgrade, `npm run doctor` confirms the installed version, data directory, service/HUD connection, and single-instance state. A notice that hooks are waiting is normal until the next trusted Codex desktop task emits a lifecycle event.

### Typing Combo permission troubleshooting

Run `npm run doctor`. When Typing Combo is enabled, it checks the installed native HUD's macOS Accessibility trust without prompting or exposing cursor coordinates. If permission is missing, open **System Settings → Privacy & Security → Accessibility**, enable the installed `codex-power-mode-overlay`, then restart Power Mode. If permission is granted but cursor effects are unavailable, bring Codex to the foreground and click inside its message input box; the next diagnostic distinguishes that focus state from a missing permission. Typing Combo can also be turned off from the menu-bar bolt, in which case Accessibility permission is not required.

The macOS menu-bar bolt is the settings entry point. Power Mode only tracks conversations opened in the Codex desktop app; CLI and subagent activity is ignored. **Status & connection** separates the current HUD display from the raw task state and lists the last real event, task origin, following policy, connection health, and full session identity. **Activity source** offers Focus, Global, and Mix: Focus protects the current conversation, Global follows the latest conversation while keeping each score isolated, and Mix combines every Codex app conversation into one shared Energy and Combo pool. **Energy gain** offers ten bounded multipliers from 0.30× to 1.50×; a change applies to the next real lifecycle event without restarting the service or HUD, and any Energy source can enter Peak at `900`. **Effect intensity** independently controls particle density and impact without changing the Focus/Arcade rhythm, and **Show Combo** can remove the agent Combo ring without spending high-frequency redraws on its hidden decay. **Typing Combo** is a separate opt-in feature that requests macOS Accessibility access, activates only while Codex is the foreground app, ignores control/navigation keys, and records only a capped count and timestamp. **Idle behavior** can keep a quiet orb or hide the HUD; when hiding is selected, **Auto-hide delay** chooses whether it disappears immediately or leaves the settled Idle orb visible for 2 or 6 seconds. **When Codex is inactive** separately controls whether the HUD hides, stays at the last Codex anchor, or follows the active app. Choose **Adjust position…** (or press `⌥⌘P`), drag the HUD inside the Codex window, and release to lock it back into click-through mode. The menu also reports historical best energy and Combo. Settings are saved immediately in the versioned `overlay-config.json` and survive overlay restarts.

Optional environment variables:

- `CODEX_POWER_MODE_EDGE`: `top-right` (default), `top-left`, `bottom-right`, `bottom-left`, or `center`.
- `CODEX_POWER_MODE_REDUCED_MOTION=1`: update the HUD without particles, flashes, or spatial motion while preserving distinct static state markers.
- `CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE=1`: keep the overlay visible while Codex is behind another app.
- `CODEX_POWER_MODE_PRESET=arcade`: increase particle density, replay cadence, and finisher intensity. The default is `focus`.
- `CODEX_POWER_MODE_INTENSITY=low|normal|high`: tune effect density independently of the semantic preset.
- `CODEX_POWER_MODE_ENERGY_GAIN=0.3|0.4|0.5|0.6|0.72|0.85|1|1.15|1.3|1.5`: choose the Energy gain multiplier. The default is balanced `0.72`.
- `CODEX_POWER_MODE_SHOW_COMBO=0`: hide the Combo bar and its decay animation.
- `CODEX_POWER_MODE_TYPING_COMBO=1`: enable the macOS-only input rhythm Combo. Accessibility permission is required; text and key values are never stored or sent.
- `CODEX_POWER_MODE_CURSOR_EFFECT=off|spark|neon`: choose the cursor-local typing effect independently from the large Typing Combo counter.
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
- Energy spans Wake, Charge, Drive, Critical, and the `900–999` Peak. A high-contrast 300-degree gauge fills within the current tier and resets only after the new topology establishes. Its bright progress head accelerates near a breakthrough. All nodes, buses, ports, stabilizers, and crown elements share one current-tier palette and one motion clock; semantic states change how that same machine moves rather than drawing another effect through the central value.
- Repeated identical read/search activity is throttled, while Act, Verify, Wait, Recover, and Complete events are never hidden by that throttle.

## Combo semantics

- Typing Combo is local and separate from the agent Combo below. At the balanced multiplier, a real `UserPromptSubmit` consumes it into a capped `4/12/23/40/65` Energy charge; the selected Energy gain multiplier scales that reward and may naturally cross the `900` Peak boundary.

- A new Codex tool step starts or extends Combo; edits add one link and successful verification adds two. Every increase pulses the ring, while tier crossings create a larger expansion.
- Observe begins draining immediately. Act gets a 15-second tool hold, Verify gets a 90-second hold, then the bar drains over 14 seconds.
- Permission waits preserve Combo for 15 seconds before draining, so approval latency is not treated as an instant failure.
- Failed verification and unverified completion break Combo immediately.
- An expired link starts again at `1×` with a brief `RELINK` / `重连` bridge; a new turn or Codex session also starts at `1×` but is deliberately not presented as a continuation.
- Combo progresses through Ignite (`1–4×`), Link (`5–9×`), Accel (`10–19×`), Heat (`20–39×`), and Extreme (`40×+`). Its critical cadence emits a double warning near expiry, then the outer ring visibly fractures once after a break.
- Passing checks use three reward tiers: restrained confirmation without a recent edit, green Boost when evidence backs the latest change, and a gold Record beat when that evidence also sets a personal best.

## Known limitations

- Power Mode supports the Codex desktop app on macOS only. Codex CLI, VS Code, subagents, Windows, and Linux are intentionally outside the current product boundary.
- The latest installed Hook is verified only when a new trusted Codex desktop task naturally emits lifecycle activity. Preview commands and synthetic render tests never count as real Hook acceptance.
- The current performance numbers are an Apple-silicon single-machine baseline. Full Xcode Instruments GPU/Energy Log inspection and a final supported macOS/Codex range remain open RC gates.
- Typing Combo and cursor-local effects require optional macOS Accessibility permission. Core lifecycle feedback works without that permission.
- The project remains private and `UNLICENSED`; no permission to redistribute or publish has been granted yet.

See the [FAQ](docs/FAQ.md) for expected behavior and the [release checklist](docs/RELEASE_CHECKLIST.md) for the remaining public-readiness gates.
