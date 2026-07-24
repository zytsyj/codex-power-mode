# Security policy

## Supported versions

Security fixes are provided for the latest `0.x` release on the `main` branch. Older development snapshots and locally modified builds are not supported.

## Report a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/zytsyj/codex-power-mode/security/advisories/new). Do not open a public issue for a suspected vulnerability.

Include the affected version, macOS version, impact, minimal reproduction steps, and whether Typing Combo was enabled. Remove prompts, source content, command bodies, tokens, usernames, absolute paths, and screenshots containing private Codex content.

You should receive an acknowledgement within seven days. Fix timing depends on severity and reproducibility; no public disclosure timeline is promised before triage is complete.

## Security boundary

Power Mode has no telemetry. Runtime HTTP traffic is loopback-only and authenticated with a per-installation token. Accessibility access is optional and used only for input-rhythm counting and insertion-point placement while Codex is foreground. See [Privacy](docs/PRIVACY.md), [Architecture](docs/ARCHITECTURE.md), and the reproducible [security audit](docs/SECURITY_AUDIT.md).
