# Changelog

## Unreleased

- Simplified Accessibility into a strict on/off flow: requesting Typing Combo or Classic mode leaves the feature off until access is granted, granting access completes the requested action automatically, and later revocation turns Typing Combo off and returns Classic mode to Focus without another system prompt.

## 0.9.2 - 2026-07-24

- Stopped the native HUD from requesting macOS Accessibility permission automatically during startup. Existing authorization still activates Typing Combo immediately, while missing authorization is now requested only after an explicit onboarding or menu action, preventing duplicate prompts for upgrading users.

## 0.9.1 - 2026-07-24

- Split HUD anchoring into two predictable modes: follow the Codex window and hide outside Codex, or remain fixed to the active screen across app and Space changes.
- Added direct right-click settings on the orb and fixed cross-window placement jumps caused by tracking unrelated foreground application windows.
- Added a first-run permission guide for Codex Hook trust and optional macOS Accessibility access, including a reliable route to the correct System Settings page and live permission detection without restarting the HUD.
- Rebuilt the GitHub project page around the current release with English/Chinese switching, native lifecycle and Energy demos, three cursor-effect showcases, complete installation guidance, and clearer public-beta boundaries.
- Explained the project's path from VS Code Power Mode to Codex-native agent feedback, including the deliberately heavier Energy weight assigned to submitted human Typing Combo input.
- Added a playful Vibe Coding disclosure: much of the implementation, refactoring, testing, and documentation was produced with Codex, while automated checks do not imply a bug-free stable release.
- Replaced the license file with the canonical MIT text while keeping the four legacy meme image sets explicitly outside the MIT grant.

## 0.9.0 - 2026-07-24

- Opened the source code, documentation, and project-authored media under MIT; added a Git-backed Codex marketplace, public contribution and security workflows, immutable CI action pins, and an explicit separate-rights notice for the four retained legacy meme image sets.
- Replaced the raw macOS overlay executable with a stable **Codex Power Mode.app** identity, added direct Accessibility onboarding and an in-menu recovery action, automatically activates cursor monitoring after permission is granted, and migrates a running legacy HUD without creating a duplicate.
- Removed position controls and saved-position text from the settings menu, replaced synchronous menu reconstruction with lightweight status refreshes, and suspend HUD mouse hit-testing while the menu is open to eliminate interaction stutter.
- Rebuilt the GitHub project landing page around the current three-mode experience, added complete English and Simplified Chinese READMEs with language switching, and replaced the legacy single-orb hero with a current Focus/Arcade/Classic overview.
- Added Classic Power Mode, a no-orb display mode that keeps cursor effects and a centered Typing Combo, automatically enables input rhythm tracking, remains fully click-through while idle, and supports direct counter dragging.
- Added six compact geometric cursor effects, a direct Chinese meme-word mode cycling through `典 / 急 / 孝 / 乐 / 绷 / 赢`, plus hands-behind-possum, fresh-cat, knife-shield-dog, and elegant-person stickers; repository-bundled transparent cutouts work offline, stay below the input baseline, and immediately replace their previous instance during rapid input.
- Made the visible HUD orb directly draggable without opening settings; only the orb hit target captures the mouse, empty overlay space remains click-through, and release saves the snapped position.
- Moved Peak to the normal `900–999` Energy tier, removed the post-edit verification gate and forced `999` completion jump, and aligned native, browser, documentation, and tests with the new boundary.
- Added a conservative RC readiness summary that detects stale cachebuster evidence and keeps automated, trusted Hook, hands-on, Instruments, and owner-decision gates separate.
- Added an ephemeral Release Candidate source-archive drill that packages only tracked files, removes the candidate after inspection, and blocks runtime state, compiled binaries, credentials, personal paths, private repository metadata, undeclared binary assets, or missing media provenance; removed private repository URLs from the plugin manifest.
- Added an isolated RC security gate covering loopback binding, token permissions, API and browser-stream authentication, origin checks, JSON and size limits, recursive sensitive-field rejection, failure isolation, and privacy-safe doctor output; POST endpoints now reject non-JSON bodies and nested secret-bearing fields.
- Reframed the README as a private Release Candidate, removed out-of-scope platform roadmap promises, documented current acceptance limits, and added a privacy-aware FAQ for lifecycle, visibility, task modes, Hook verification, Accessibility, performance, and publication status.
- Added a native peak layer/animation budget self-test for simultaneous Energy breakthrough, semantic transition, Typing Combo, cursor milestone, and prompt injection choreography across Focus, Arcade, and Reduce Motion.
- Added a recoverable real-interaction RC checklist that snapshots non-sensitive HUD settings, records only predefined manual outcomes, and atomically restores the baseline without automatically claiming visual acceptance.
- Added a read-only Hook runtime storage audit and a tested candidate retention policy that keeps the newest eight versions plus the linked current runtime; automatic deletion remains disabled pending real Hook acceptance.
- Added an isolated native settings persistence self-test covering save/reload, validation, position reset, language, idle, inactive-app, motion, Combo, and cursor preferences without touching installed user settings.
- Extracted the native event-stream retry policy into a Swift-tested 1/2/4/8/16/30-second schedule with a 10-second healthy-connection reset, and added both reconnect and placement self-tests to macOS CI.
- Added a bounded live reconnect check that rejects three local stream attempts, measures the real 1/2/4-second cadence, and verifies automatic recovery without injecting lifecycle activity or changing settings.
- Added a reproducible 324-frame RC compatibility report that verifies native theme, motion, state, Energy, completion, cursor, and Typing Combo coverage while explicitly separating synthetic evidence from real lifecycle and hands-on acceptance.
- Added a bounded RC stability check that forces an authenticated service restart, verifies native HUD reconnection and settings preservation, and stress-tests concurrent startup without touching real task state.
- Added a reproducible macOS RC performance sampler, regression budgets, and documented single-machine baseline covering idle, the complete semantic lifecycle, Typing Combo, and Energy breakthroughs without touching real task data.
- Added compact reproducible Focus and Arcade GIF storyboards composed entirely from privacy-safe synthetic native frames with macOS system tooling.
- Added first-party privacy-safe light/dark preview media, README visual and control summaries, media provenance, and a reproducible native QA rendering command.
- Added verified private-install, upgrade, Accessibility, troubleshooting, reset, purge, and uninstall guidance with automated documentation gates.
- Added an explicit dependency and license inventory, third-party notice baseline, release checklist gates, and automated protection for the current zero-package private build.
- Added public-readiness architecture, privacy, contribution, conduct, security, and release-checklist documentation while keeping the package private and the license explicitly unapproved until the owner makes that decision.
- Extended `doctor` with a privacy-preserving native Accessibility check that distinguishes Typing Combo being disabled, missing macOS permission, granted permission, and a Codex input box that is not currently focused.
- Added guarded maintenance commands to stop Power Mode, restore display defaults without losing history, and purge only a recognized Power Mode data directory before uninstalling; destructive commands require explicit `--yes` confirmation.
- Added a concise `doctor` command with human-readable and JSON output for service/HUD health, version and data-directory consistency, duplicate instances, stream connection, and trusted Codex lifecycle activity.
- Added a release-hygiene gate and matching root ignores so developer-specific home paths, private-key material, local state, service tokens, logs, and compiled overlay artifacts cannot accidentally enter a future public release.
- Restyled Typing Combo as a prominent orb-matched energy readout: the floating number and balanced gradient lifetime line advance together through cyan, mint, violet, pink, and gold tiers, with a warm critical drain and clearer hit pulses but no enclosing badge or heavy track.
- Raised semantic-state transitions from merely legible to attention-leading: Energy material now briefly ducks behind a larger staged signature reveal, the phase rail draws itself on, the center glyph punches in, and persistent outlines and activity labels are heavier and brighter without increasing steady-state particle load.
- Isolated Energy, semantic-state, and Combo choreography layers so simultaneous events no longer erase one another; high Energy now adds dark contrast underlays and stronger phase-colored signatures, rails, and glyph shadows so every state remains legible through Critical and Peak effects.
- Lengthened Energy tier crossings into a readable fill-hold, compression, breakthrough, tier-seal, and settling rhythm; higher tiers now scale their impact width, alternating accent rings, glow, rotation, and aftershock density while Focus remains restrained and Arcade escalates further.
- Split cursor feedback into restrained upward Spark shards and a dual-line Neon caret with orbiting glow particles; Typing Combo stages now shift the palette and trigger larger milestone rings at 5/10/20/40/80/120/200 without increasing steady-state layer load.
- Restored cursor effects by enabling Codex's deep Chromium accessibility tree, traversing its navigation/row relations, collapsing the selected text-marker range to its real endpoint, accepting zero-width insertion rectangles, invalidating stale composer nodes, and strengthening the true-caret pulse without a fixed-position fallback.
- Separated semantic state grammar from the Energy progress ring with an independent inner rail, preserving Observe, Act, Verify, Wait, Recover, and four Complete outcomes across low, middle, and high Energy tiers.
- Expanded native render QA into a state-by-Energy matrix covering light/dark, Focus, Arcade, Reduce Motion, and verified, unverified, cancelled, or no-change completion silhouettes.
- Separated all seven Energy tiers with dedicated two-color materials, ring textures, node counts, glow depths, orbit directions, and breathing cadences while retaining one circular orb silhouette.
- Added deterministic native light/dark render QA for Focus, Arcade, and Reduce Motion, and avoided a macOS 26 QuartzCore crash by assigning each tier's dash pattern directly.
- Fixed the Energy-tier pulse keyframes and strengthened each upgrade or downgrade with ring compression, a line-weight impact, and staggered breakthrough or vent waves.
- Moved the Typing Combo lifetime rail onto a continuous Core Animation drain, eliminating stepped rollback between low-frequency idle updates.
- Choreographed prompt injection as a visible Combo collapse, convergence beat, and delayed particle stream into the orb.
- Separated Typing Combo from the orb into a large adjacent `×N` counter, added optional cursor Sparks/Neon effects with accessibility and window fallbacks, and ignored deletion and shortcut keys.
- Restricted Typing Combo injection to Codex's real `UserPromptSubmit` understanding event, removing unreliable Enter-key inference and sampling the rendered caret after the editor advances.
- Followed Chromium editor carets through a read-only event tap and the deepest accessibility text area with real range-bound support; removed static composer/window coordinate fallbacks so cursor particles either follow the insertion point or stay hidden.
- Installed lifecycle Hook code behind a stable, atomically updated plugin-data path so cachebuster upgrades cannot strand already-open Codex tasks on a removed plugin version.
- Standardized every Energy tier on the same circular orb silhouette while preserving stronger tier identity through color, glow depth, ring cadence, ticks, and breakthrough intensity.
- Reworked Energy as a per-tier refill loop: the ring fills, breaks through, resets at the next tier, and reverses through a drain/restore sequence on decay.
- Gave all seven Energy tiers distinct color, node density, line weight, glow, and high-tier instability so tier changes are visible without changing the circular orb silhouette.
- Added an opt-in macOS Typing Combo while Codex is foreground, with a short lifetime meter and milestone pulses that never capture or persist text.
- Consumed Typing Combo only after a real `UserPromptSubmit`, then animated its collapse into the orb and applied a bounded authenticated Energy injection without advancing the agent Combo or allowing an unverified `999` peak.
- Expanded Energy to `0–999` with seven visible tiers, real-time inactivity decay, stage breakthrough/vent animations, and an evidence-backed verified peak.
- Added Combo growth pulses, five count stages, a critical double warning, relink recovery, and an explicit compositor-driven fracture on natural or forced disconnect.
- Added Mix activity mode, combining all Codex desktop conversations into one Energy/Combo pool while retaining isolated Focus and latest-task Global behavior.
- Reconciled inactive conversation energy against elapsed time and added a 780 ms orb/ring handoff so Global task switches no longer look like unexplained counter jumps.
- Added a multi-track orbit when more than one Codex conversation is active in Mix, without allowing one parallel stop or failure to reset the shared chain.
- Replaced the live HUD's timer-driven drawing path with a Core Animation layer renderer so semantic motion, fades, energy, Combo decay, and event particles are composited by macOS.
- Reduced the floating UI to one draggable orb: concise activity text now sits inside the core, Combo is the outer lifetime ring, and the expanded confidence/evidence card is gone.
- Refined the orb into a calmer glass form with larger type, cleaner dual rings, lower-saturation phase colors, softer event particles, and no instrument-panel ornaments.
- Removed the development-only “Always expanded” idle mode; existing settings migrate to “Keep orb”.

## 0.8.0 - 2026-07-22

- Limited native Arcade redraws to the HUD and active effect damage region, and localized flash/recovery feedback around the orb instead of repainting the full Codex window at 60 Hz.
- Added per-installation authentication for hooks, diagnostics, previews, and the native event stream, with a private `0600` token that remains outside the plugin package.
- Isolated the browser HUD behind a same-origin bootstrap and a process-scoped stream-only token, removed permissive SSE cross-origin access, and rejected foreign browser origins.
- Added strict lifecycle event validation and safe `400`/`413` responses so malformed JSON, oversized requests, sensitive fields, and invalid state signals cannot crash or poison the service.
- Rebuilt displayed state from the hook-owned per-session snapshot instead of trusting state supplied in the HTTP request.
- Marked the current private build as the first self-use stable baseline after connection, lifecycle, Combo, semantic animation, positioning, settings, and performance milestones passed release regression.
- Serialized native HUD startup so concurrent Codex task launches cannot race into duplicate overlays.
- Validated PID ownership before reusing or stopping a native HUD, preventing a stale PID file from targeting an unrelated process after macOS reuses an identifier.
- Waited for the newly launched native process to become identifiable before releasing the startup lock, closing the final concurrent-launch window found by an eight-way stress test.
- Preserved an unset custom position as `null` across restarts instead of coercing it to the bottom-left coordinate, eliminating position drift during upgrades.
- Normalized settled HUD diagnostics to `Combo 0 / Idle` while preserving the completed task's raw Combo and historical best values separately.
- Passed isolated concurrent launch, stale-PID safety, forced service restart, automatic stream reconnection, settings preservation, and real Codex Desktop lifecycle checks.

## 0.6.23 - 2026-07-21

- Split Act and Verify into different visual grammars across native and browser HUDs: Act now drives left-to-right through a thrust axis, while Verify closes four lock brackets onto a central verdict marker.
- Preserved the directional Act and symmetric Verify silhouettes in Reduced Motion so the states remain identifiable without relying on animation or color.
- Served browser HUD `.mjs` dependencies as JavaScript and covered their MIME type, restoring live preview execution instead of leaving the mirror frozen at its default state.
- Grouped native diagnostics under a bilingual Status & Connection menu with separate HUD display, raw task state, last real event, task origin, following policy, and session identity rows.
- Renamed status output to `hudDisplay` and `taskState`, and added current/last event source plus last real event type to connection diagnostics.
- Suspended the browser HUD presentation timer after a settled auto-hide, with immediate wake-up on new activity, disconnect, and reconnect events.
- Kept a 100 ms cadence only while energy or Combo is visibly changing and reduced static visible states to a one-second heartbeat.
- Added an auto-hide delay setting with immediate, 2-second, and 6-second choices, so the quiet Idle orb can bridge the transition between energy settling and the HUD disappearing.
- Disabled browser caching for local HUD assets so cachebuster reinstalls and development restarts cannot leave an older visual runtime on screen.
- Replaced the ambiguous inactive-Codex visibility toggle with explicit Hide, Stay over Codex, and Follow active app policies in English and Chinese.
- Migrated the previous enabled setting to Stay over Codex, then removed the legacy boolean from newly saved configuration.
- Kept dragged and preset HUD positions inside the active display's visible area after Dock, resolution, or monitor-layout changes.
- Re-evaluated the Codex window and safe placement area immediately when macOS display parameters change, preventing removed monitors from stranding the HUD off-screen.
- Added one-shot energy tier upgrades so Charge, Flow, Surge, and Overdrive crossovers have progressively stronger Focus and Arcade beats.
- Gave Flow, Surge, and Overdrive distinct 4/8/12-node outer geometry, with a separate Overdrive ring that remains readable in Reduced Motion.
- Split successful verification into confirmation, evidence-backed reward, and new-record feedback instead of giving every passing check the same climax.
- Added a gold RECORD Combo stage and bilingual new-best copy while preserving green for ordinary evidence and dashed green for standalone confirmation.
- Added a short cyan RELINK stage when useful work resumes after natural Combo expiry, without treating a new turn or task as a continuation.
- Split the expired Combo rail and emit one restrained break impact so critical countdown, disconnect, and reconnection have distinct rhythms.
- Increased Arcade's critical cadence while keeping Focus and Reduced Motion calmer and structurally readable.
- Added event-generation guards so delayed scan echoes, repair passes, typing pulses, and chained bursts cannot leak into a newer HUD state.
- Reduced native wakeups for a fully hidden, settled HUD from four per second to one while retaining immediate 60 Hz event recovery.
- Preserved prompt-understanding semantics in Reduced Motion with a static four-way focus lock distinct from context scanning.
- Gave prompt submission a converging focus effect while preserving the horizontal scan for file and context reads.
- Added persistent completion silhouettes: a verified check, an unverified dashed warning, and a cancelled broken-ring cross.
- Turned Recover into a two-stage fracture-and-reassembly effect with converging repair fragments and visible seam stitches.
- Changed Wait from a smooth pulse into a double-beat gate alarm with paired amber attention streams.
- Reworked Verify into four evidence lanes converging on a square core with a four-corner lock silhouette.
- Gave Act a directional three-chevron silhouette and leftward rectangular drive burst so it no longer reads like Observe or Verify.
- Entered Observe immediately on `UserPromptSubmit` while deliberately discarding prompt text.
- Scoped lifecycle tracking to Codex desktop conversations so CLI and subagent activity cannot drive the HUD.
- Added session-source diagnostics to state and service health output.
- Moved the default manual runtime state to `~/.codex/power-mode` so stale demo history cannot be copied into local plugin installations.
- Preserved Codex-provided `PLUGIN_DATA` as the highest-priority storage location for installed hooks.

## 0.6.22 - 2026-07-21

- Synced streamed hook state into the active service data directory so SSE reconnects cannot fall back to stale demo or pre-install state.
- Kept event history single-sourced in the hook data directory while persisting only the already-reduced state snapshot in the service.

## 0.6.21 - 2026-07-21

- Preserved distinct static Observe, Act, Verify, Wait, Recover, and Complete markers when reduced motion is enabled.
- Removed the transient flash layer entirely in reduced-motion mode so it cannot linger as a persistent glow.

## 0.6.20 - 2026-07-21

- Paused the browser effects canvas when no particles, rings, or scans are active, then resumed it on the next Codex event.

## 0.6.19 - 2026-07-21

- Corrected the native no-change completion copy so a turn without code edits no longer recommends unnecessary verification.

## 0.6.18 - 2026-07-21

- Distinguished unverified completion with a yellow UNVERIFIED label and single verification reminder ring.
- Kept no-change completion neutral cyan while preserving green exclusively for evidence-backed completion.

## 0.6.17 - 2026-07-21

- Rendered cancelled approvals as an amber CANCELLED outcome instead of a green success-like completion.
- Added a restrained double-ring cancellation signal while reserving the green finisher for verified completion.

## 0.6.16 - 2026-07-21

- Added dedicated directional fragment feedback when Codex cannot apply an edit.
- Distinguished edit failures from verification failures with a double red impact and stronger fault shake.

## 0.6.15 - 2026-07-21

- Added explicit ONLINE and RECONNECTING feedback without replacing the six semantic Codex states.
- Kept a compact amber connection marker visible after the native HUD collapses during an outage.

## 0.6.14 - 2026-07-21

- Added capped exponential backoff when the native event stream cannot reach the service.
- Cleaned up completed sessions before reconnecting and reset the retry delay as soon as service data returns.

## 0.6.13 - 2026-07-21

- Expanded `npm run status` with service health, native PID, launch configuration, and semantic state.
- Persisted normalized native edge, scale, preset, and accessibility settings for reliable diagnostics.

## 0.6.12 - 2026-07-21

- Reduced the native overlay refresh loop from 60Hz to 4Hz while idle or holding a static Combo.
- Kept particles, semantic motion, and Combo decay at 60Hz, restoring full speed immediately when an event arrives.

## 0.6.11 - 2026-07-21

- Followed the foremost on-screen Codex window instead of selecting the largest window.
- Prevented the overlay from jumping to a larger background Codex window in multi-window workflows.

## 0.6.10 - 2026-07-21

- Kept the expanded HUD inside narrow Codex windows with a 12px safe edge.
- Added matching responsive behavior to the browser preview without shrinking the normal desktop layout.

## 0.6.9 - 2026-07-21

- Limited LOST feedback to a 3.2-second disconnect window before returning the Combo rail to READY.
- Applied the same timing to explicit failures and natural Combo expiry in browser and native overlays.

## 0.6.8 - 2026-07-21

- Treated a turn stopping while permission is still pending as an explicit cancelled completion.
- Broke Combo immediately and surfaced approval cancellation instead of returning to READY.

## 0.6.7 - 2026-07-21

- Added an explicit failed-edit lifecycle event that enters Recover without incrementing edit counts.
- Broke Combo immediately when Codex cannot apply a change instead of waiting for natural decay.

## 0.6.6 - 2026-07-21

- Prevented failed patch responses from being recorded as successful edit events.
- Kept edit counts, Momentum, and Combo free of work that Codex did not actually apply.

## 0.6.5 - 2026-07-21

- Added support for Codex freeform `apply_patch` hook input and common object aliases.
- Restored accurate edit counts and Combo continuation when patches are delivered as raw text.

## 0.6.4 - 2026-07-21

- Added lifecycle hook compatibility for Codex `exec_command` tools and their `cmd` input field.
- Routed command start, verification result, and permission events through the same semantics as the legacy `Bash` alias.

## 0.6.3 - 2026-07-20

- Gave Observe a persistent single-direction radar sweep in both browser and native macOS overlays.
- Kept the scan quieter than Act and Verify while preserving a distinct ongoing reading state.

## 0.6.2 - 2026-07-20

- Gave Act a persistent outward-propagating shard signal in both browser and native macOS overlays.
- Made ongoing action directionally opposite to Verify's inward focus instead of relying on color alone.

## 0.6.1 - 2026-07-20

- Gave Verify a persistent three-segment orbit and inward focus pulse in both browser and native macOS overlays.
- Preserved reduced-motion behavior while keeping Verify geometrically distinct from Observe and Act.

## 0.6.0 - 2026-07-20

- Integrated the redesigned reactor and telemetry frontend from `main` without losing semantic state effects.
- Added Codex-native Combo state, best-link tracking, expiry, decay, wait grace, turn/session reset, and explicit break handling.
- Added an always-visible Combo count and decay rail to both browser and native macOS overlays.
- Added coverage for hold, decay, expiry, verification failure, new-turn reset, and new-session reset.

## 0.5.8 - 2026-07-20

- Gave verified Complete a persistent three-color finish halo and check marker in both overlays.
- Kept unverified completion free of celebratory markers so the visual language remains evidence-backed.

## 0.5.7 - 2026-07-20

- Gave Recover a persistent fractured ring and repair seam in both native and browser overlays.
- Kept the recovery marker static when reduced motion is enabled.

## 0.5.6 - 2026-07-20

- Gave Wait a persistent amber breathing-gate signal around the HUD core in both native and browser overlays.
- Added an explicit preview phase query for repeatable light and dark visual acceptance checks.

## 0.5.5 - 2026-07-20

- Made the Codex `SessionStart` hook automatically ensure the native macOS overlay is running.
- Reused the existing server and native-process guards to avoid duplicate overlays across sessions.
- Added `CODEX_POWER_MODE_AUTO_NATIVE=0` for users who only want the background event service.
- Added startup-policy tests and included the session hook in syntax validation.

## 0.5.4 - 2026-07-20

- Coalesced identical rapid Observe events so consecutive reads and searches do not repeatedly restart the scan animation.
- Added a configurable Observe throttle without suppressing phase changes, edits, verification, permission, recovery, or completion events.
- Added storage-level coalescing tests to cover persistence and state accounting.

## 0.5.3 - 2026-07-20

- Added hard effect budgets for particles, shockwaves, and scan beams in both native and browser overlays.
- Tuned separate Focus and Arcade limits to prevent high-frequency Codex tool activity from causing unbounded animation buildup.

## 0.5.2 - 2026-07-17

- Increased the default HUD to a balanced 78pt and added configurable `0.75×–1.6×` scaling.

## 0.5.1 - 2026-07-17

- Reduced the native HUD from 96pt to 60pt and added a compact high-contrast status capsule.
- Added a real Momentum progress arc that remains readable over light and dark Codex themes.
- Gave Observe, Act, Verify, Wait, Recover, and Complete distinct geometry and motion.
- Replaced recovery dots with directional rectangular fragments and introduced inward verification charge.

## 0.5.0 - 2026-07-17

- Added auto-collapse and Focus/Arcade visual presets.
- Reworked the overlay into a minimal energy orb with short-lived semantic status copy.
- Added distinct scan, action, charge, attention, recovery, and verified-completion choreography.

## 0.4.0 - 2026-07-17

- Replaced line-volume combo scoring with Codex-native Momentum, Confidence, Risk, and Evidence.
- Added Observe, Act, Verify, Wait, Recover, and Complete semantic states.
- Added pre-tool and permission-request feedback.
- Redesigned the HUD as a compact transparent component floating over Codex.
- Updated the native macOS overlay for semantic states and evidence-backed completion.
- Added replay of recent local events for effect development.
- Stopped persisting verification command text.

## 0.3.0 - 2026-07-17

- Made the Codex desktop window the exclusive native Power Mode surface.
- Added automatic Codex window discovery, movement, resizing, clipping, and inactive-window hiding.
- Added virtual typing replay scaled by patch character count.
- Added shockwaves, deletion sparks, combo shake, danger borders, and stronger verification finishers.
- Removed the planned VS Code bridge from the roadmap.

## 0.2.0 - 2026-07-17

- Added a native macOS transparent, click-through overlay.
- Added multi-display and screen-edge positioning.
- Added automatic reduced-motion behavior and an explicit override.
- Added native overlay start, duplicate-process protection, and clean stop commands.
- Added macOS native compilation to continuous integration.

## 0.1.0 - 2026-07-17

- Added Codex lifecycle hooks for patch, verification, and turn completion events.
- Added local combo and verification state engine.
- Added zero-dependency real-time particle HUD.
- Added test, build, lint, and type-check command classification.
- Added verified Victory and failed-verification Danger states.
