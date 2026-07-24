# Installation and maintenance

Codex Power Mode `0.9.0` is an open-source public beta for the Codex desktop app on macOS.

## Requirements

- macOS with Codex desktop installed.
- Node.js 20 or newer available to Codex hooks.
- The system Swift toolchain for compiling the native HUD locally.
- macOS Accessibility permission only when the optional Typing Combo or cursor effects are enabled.

## Install from GitHub

Add the repository as a marketplace and install the plugin:

```bash
codex plugin marketplace add zytsyj/codex-power-mode
codex plugin add codex-power-mode@codex-power-mode
```

Start a new Codex task after installation so Codex can load the plugin hooks and skill. Review and trust the hooks when Codex asks. The first trusted desktop task starts the authenticated local service and native HUD automatically.

On first launch, Power Mode shows a one-time permission guide covering both confirmations. Codex owns the Hook trust prompt, so it must be approved inside Codex. The guide can continue in basic mode without Accessibility, enable Typing Combo and open the correct Accessibility panel, or defer the choice. Reopen it at any time from the menu-bar bolt under **Permissions & first-time setup…**.

Run the installed control script's `doctor` command to confirm the running version, shared data directory, one service, one HUD, stream connection, Accessibility state, and lifecycle events. In a source checkout, the equivalent is:

```bash
npm run doctor
```

The service binds to `127.0.0.1:4737`. Installed runtime data is stored separately from the versioned plugin cache so settings and history survive replacement of the package.

### Hook runtime storage audit

Each upgrade keeps a versioned Hook runtime so already-open Codex tasks never point into a removed plugin cache. Inspect this storage without deleting anything:

```sh
npm run audit:hook-runtimes
```

The current release only reports a candidate policy: keep the newest eight runtimes and always protect the version selected by the stable `hook-runtime` link. Automatic cleanup remains disabled until real post-upgrade Hook acceptance is complete.

## Upgrade

Refresh the Git-backed marketplace and reinstall the plugin:

```bash
codex plugin marketplace upgrade codex-power-mode
codex plugin add codex-power-mode@codex-power-mode
```

After reinstalling:

1. Start a new Codex task so the updated hook and skill are loaded.
2. Run `npm run doctor` from the matching source checkout or the installed control script.
3. Confirm the installed and running versions match, the data directory is unchanged, and only one service and one HUD are running.
4. Confirm the previous display settings, position, history, and personal best remain available.

If the running version is stale, stop Power Mode with the old installed control script, reinstall once, then start a new task. Do not launch multiple cached copies manually.

## Accessibility permission

Typing Combo is opt-in. Enable it from the menu-bar bolt. Power Mode asks macOS for permission and opens **System Settings → Privacy & Security → Accessibility**; turn on **Codex Power Mode** once. If the system prompt was dismissed, choose **Grant cursor access…** from the bolt menu. Power Mode watches the permission state and starts input rhythm and cursor-local effects as soon as access is granted—there is no app dragging and no HUD restart.

If `doctor` reports that permission is granted but the cursor is unavailable, bring Codex to the foreground and click its message input. Diagnostics report only capability state; they do not print the text or cursor coordinates. Disable Typing Combo to run without Accessibility permission.

## Stop, reset, and remove

- `npm run stop` stops the HUD and local service without deleting data.
- `npm run reset:settings -- --yes` restores display defaults while preserving history and personal best.
- `npm run purge:data -- --yes` stops Power Mode and deletes only a recognized Power Mode data directory. It removes settings, history, and the local token.
- `codex plugin remove codex-power-mode@codex-power-mode` removes the plugin package.

For a complete removal, purge data first, remove the plugin, and optionally remove the marketplace with `codex plugin marketplace remove codex-power-mode`. Revoke Accessibility permission in System Settings if it is no longer needed. The purge command refuses filesystem roots and unrelated directory names.

## Public-beta limitations

- macOS 13 or newer is the build target, but the full macOS/Codex compatibility range has not completed broad public validation.
- The native HUD is installed as a stable local **Codex Power Mode.app** bundle. Source builds use ad-hoc signing unless `CODEX_POWER_MODE_CODESIGN_IDENTITY` names an available signing identity. A Developer ID-signed and notarized binary is still required before claiming seamless permission continuity across every binary-changing upgrade.
- Four optional legacy meme sticker sets are excluded from MIT; see `THIRD_PARTY_NOTICES.md`. Removing them leaves all semantic HUD behavior and the remaining cursor effects intact.
- Existing tasks may retain the prior plugin skill until a new task is opened after an upgrade.

## Installation acceptance

Before calling a build stable, verify a fresh install, an in-place upgrade, settings preservation, single-instance startup, stop, reset, purge, package removal, and permission revocation. Record the supported macOS, Codex, Node.js, and Swift versions used for the Release Candidate.
