# Installation and maintenance

Codex Power Mode is still a private incubation build. The commands below describe the owner's current personal-marketplace installation. A public installation channel will be documented only after the repository and first release are explicitly approved.

## Requirements

- macOS with Codex desktop installed.
- Node.js 20 or newer available to Codex hooks.
- The system Swift toolchain for compiling the native HUD locally.
- macOS Accessibility permission only when the optional Typing Combo or cursor effects are enabled.

## Private installation

Install the current private build from the configured personal marketplace:

```bash
codex plugin add codex-power-mode@personal
```

Start a new Codex task after installation so Codex can load the plugin hooks and skill. Review and trust the hooks when Codex asks. The first trusted desktop task starts the authenticated local service and native HUD automatically.

Run the installed control script's `doctor` command to confirm the running version, shared data directory, one service, one HUD, stream connection, Accessibility state, and lifecycle events. In a source checkout, the equivalent is:

```bash
npm run doctor
```

The service binds to `127.0.0.1:4737`. Installed runtime data is stored separately from the versioned plugin cache so settings and history survive replacement of the package.

## Upgrade

Private development upgrades use the plugin cachebuster helper and reinstall from the same personal marketplace. Do not edit marketplace configuration by hand. After reinstalling:

1. Start a new Codex task so the updated hook and skill are loaded.
2. Run `npm run doctor` from the matching source checkout or the installed control script.
3. Confirm the installed and running versions match, the data directory is unchanged, and only one service and one HUD are running.
4. Confirm the previous display settings, position, history, and personal best remain available.

If the running version is stale, stop Power Mode with the old installed control script, reinstall once, then start a new task. Do not launch multiple cached copies manually.

## Accessibility permission

Typing Combo is opt-in. Enable it from the menu-bar bolt, then allow the installed `codex-power-mode-overlay` under **System Settings → Privacy & Security → Accessibility**. Restart Power Mode after changing permission.

If `doctor` reports that permission is granted but the cursor is unavailable, bring Codex to the foreground and click its message input. Diagnostics report only capability state; they do not print the text or cursor coordinates. Disable Typing Combo to run without Accessibility permission.

## Stop, reset, and remove

- `npm run stop` stops the HUD and local service without deleting data.
- `npm run reset:settings -- --yes` restores display defaults while preserving history and personal best.
- `npm run purge:data -- --yes` stops Power Mode and deletes only a recognized Power Mode data directory. It removes settings, history, and the local token.
- `codex plugin remove codex-power-mode@personal` removes the private plugin package.

For a complete removal, purge data first and then remove the plugin. Revoke Accessibility permission in System Settings if it is no longer needed. The purge command refuses filesystem roots and unrelated directory names.

## Known private-build limitations

- macOS and Codex compatibility ranges have not completed Release Candidate validation.
- The native executable is compiled locally and is not yet signed or notarized as a distributed application.
- A public installation source, public security-reporting channel, open-source license, and stable release version have not been chosen.
- Existing tasks may retain the prior plugin skill until a new task is opened after an upgrade.

## Installation acceptance

Before calling a build stable, verify a fresh install, an in-place upgrade, settings preservation, single-instance startup, stop, reset, purge, package removal, and permission revocation. Record the supported macOS, Codex, Node.js, and Swift versions used for the Release Candidate.
