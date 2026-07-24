# Contributing

Contributions are welcome through GitHub issues and pull requests. By submitting a contribution, you agree that it may be distributed under the project's MIT license.

## Development principles

- Treat the HUD as a semantic Codex activity indicator, not a keystroke or code-volume reward.
- Keep the surface transparent, compact, directly draggable, and specific to the Codex desktop app.
- Never persist prompts, source text, typed characters, command bodies, secrets, or cursor coordinates.
- Keep Focus restrained, Arcade expressive, Classic free of orb/state remnants, and Reduce Motion semantically complete.
- Avoid unbounded particles, duplicate processes, hidden high-frequency redraws, and destructive maintenance defaults.
- Do not add third-party media without verifiable redistribution terms and an updated notice.

## Before opening a pull request

1. Keep the change focused and add regression coverage.
2. Run `npm run check` and compile the native Swift overlay.
3. For visuals, render the relevant light/dark, Focus/Arcade/Classic, and Reduce Motion samples.
4. For lifecycle changes, verify real Codex desktop events without storing content.
5. For installation changes, test fresh install, upgrade preservation, health diagnosis, and safe removal.
6. Use synthetic or fully redacted screenshots.

Do not commit generated runtime data, local binaries, logs, signing credentials, screenshots containing private content, or developer-specific absolute paths.

Security reports belong in [GitHub private vulnerability reporting](https://github.com/zytsyj/codex-power-mode/security/advisories/new), not a pull request or public issue.
