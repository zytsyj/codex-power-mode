# Frequently asked questions

## What is Power Mode?

Power Mode is a compact native macOS HUD for the Codex desktop app. It translates real Codex lifecycle events into Observe, Act, Verify, Wait, Recover, and Complete states, plus Energy and Combo feedback. It is an activity indicator, not a claim about model internals or percentage-complete progress.

## Is this the same as VS Code Power Mode?

No. Typing Combo borrows the immediate rhythm of editor Power Mode, but the orb primarily reflects Codex work: understanding, reading, editing, verification, waits, recovery, completion, decay, and disconnects. There is no VS Code bridge or independent dashboard.

## Which Codex surfaces are supported?

Only the Codex desktop app on macOS. Codex CLI, subagents, VS Code, Windows, and Linux are intentionally ignored or unsupported in the current product scope.

## Does it read or save what I type?

No. The optional Typing Combo uses a listen-only event tap to count eligible rhythm without receiving character values. Accessibility APIs are used only to locate the current insertion-point rectangle for cursor effects. Power Mode does not persist prompts, code, key values, command text, authentication data, or cursor coordinates.

## Why does `realEventsReceived` show `0`?

The latest installed Hook has not yet been exercised by a new trusted Codex desktop task. Start a new Codex desktop task, send a real prompt, and let it use a tool; then run `npm run doctor`. Demo, showcase, replay, direct HTTP requests, and synthetic tests intentionally do not satisfy this gate.

## Why is the orb hidden while idle?

The default Idle behavior hides the settled HUD after its configured delay. From the menu-bar bolt, choose the quiet-orb option to keep a neutral `0 / Idle` orb instead. Wait, Recover, and reconnect states remain visible.

## Why is the HUD hidden or moved when Codex is not active?

The **When Codex is inactive** setting has three policies: hide it, keep it at the last Codex anchor, or follow the foreground app. This is independent from Focus, Global, and Mix, which decide which Codex desktop task supplies activity.

## What are Focus, Global, and Mix?

- **Focus** holds the current Codex task and prevents background tasks from taking over.
- **Global** follows the latest active Codex desktop task while keeping each task's Energy and Combo isolated.
- **Mix** combines all Codex desktop tasks into one shared Energy and Combo pool. Each conversation end still flashes its own completion result without resetting the pool; after the final conversation, the shared energy eases down in Idle rather than disappearing.

## Why do cursor effects require Accessibility permission?

macOS requires Accessibility access to obtain the insertion-point bounds exposed by Codex's Chromium editor. Power Mode does not use that permission to read text. Disable Typing Combo to remove the requirement; lifecycle and orb feedback continue to work.

## How do I check whether it is running correctly?

Run `npm run doctor`. A healthy result shows one local service, one native HUD, matching versions and data directories, and a connected event stream. A Hook warning is expected immediately after an upgrade until a new trusted Codex desktop task emits an event.

## Is the performance report a GPU benchmark?

No. The automated report measures CPU, memory, macOS `top` POWER, threads, context switches, and peak Core Animation layer/animation counts. Final GPU and Energy Log acceptance requires full Xcode Instruments and testing across the eventual support range.

## Is the project open source yet?

No. The repository remains private and `UNLICENSED`. Documentation and release gates are being prepared for a possible public release, but publication, repository visibility, license choice, supported versions, and the first release number all require explicit owner approval.

Run `npm run readiness:rc` for a conservative snapshot. `passed` means evidence matches the current cachebuster build; `stale` means an older build passed and must be rerun. Synthetic rendering never satisfies the trusted-Hook or hands-on-interaction gates, and even complete automation cannot resolve owner decisions or authorize publication.

## Where should I start when something looks wrong?

Use [Troubleshooting](TROUBLESHOOTING.md) for connection, Accessibility, duplicate-process, stale-version, cursor, and visibility checks. Installation, upgrade, reset, purge, and removal are documented in [Installation](INSTALLATION.md).
