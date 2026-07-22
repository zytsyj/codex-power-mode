# Contributing

Codex Power Mode is in private incubation. External contributions are not accepted until the repository is explicitly opened.

## Development principles

- Treat the HUD as a semantic Codex activity indicator, not a keystroke or code-volume reward.
- Keep the surface transparent, compact, draggable, and specific to the Codex desktop app.
- Never persist prompts, source text, typed characters, command bodies, secrets, or cursor coordinates.
- Keep Focus restrained, Arcade expressive, and Reduce Motion semantically complete.
- Avoid unbounded particles, duplicate processes, hidden high-frequency redraws, and destructive maintenance defaults.

## Before submitting a change

1. Keep the change focused and add regression coverage.
2. Run `npm run check` and compile the native Swift overlay.
3. For visuals, render light/dark Focus, Arcade, and Reduce Motion samples.
4. For lifecycle changes, verify real Codex desktop events without storing content.
5. For installation changes, test fresh install, upgrade preservation, health diagnosis, and safe removal behavior.

Do not include generated runtime data, local binaries, logs, screenshots containing private content, or developer-specific absolute paths.
