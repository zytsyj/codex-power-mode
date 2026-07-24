# Media provenance

The checked-in preview images are first-party frames rendered directly from the native Core Animation implementation. They contain synthetic state only: no Codex window, prompt, source code, user name, local path, cursor coordinate, or runtime history.

`hero.svg` is a first-party, hand-authored vector composition derived from the same semantic palette and connected-machine geometry. It presents the current Focus, Arcade, and no-orb Classic Power Mode alongside the five-tier Energy evolution. It contains no external assets, embedded fonts, scripts, user data, or runtime content.

## Reproduce the QA set

On macOS with the system Swift toolchain:

```bash
npm run render:qa
```

This compiles a temporary native renderer and writes the complete 326-frame matrix to the ignored `.power-mode/render-qa` directory. The matrix covers light/dark, Focus/Arcade/Reduce Motion, all five Energy tiers, six semantic states at low/mid/high Energy, four completion outcomes, tier transitions, nineteen cursor-effect samples, Typing Combo colors, and dedicated no-orb Classic Power Mode frames.

The six PNG images under `docs/media/` are selected unchanged from that generated matrix:

- `focus-light-verify.png`
- `arcade-dark-act.png`
- `arcade-dark-complete.png`
- `typing-combo-dark.png`
- `classic-mode-dark.png`
- `reduced-light-recover.png`

Two compact animated storyboards are composed from the same synthetic frames with macOS ImageIO:

- `focus-demo.gif` — Observe → Act → Verify → Complete.
- `arcade-demo.gif` — cursor/Typing Combo → Observe → Act → Energy breakthrough → Verify → Complete.

Rebuild the GIFs in the ignored `.power-mode/render-demos` directory with:

```bash
npm run render:demos
```

The Focus GIF has four frames and lasts 3.55 seconds. The Arcade GIF has eight frames and lasts 5 seconds. They are deliberately small animated summaries, not recordings of a real Codex window and not frame-perfect captures of every transient particle.

Regenerate and visually inspect the matrix and demos after any native visual change. Do not replace these files with screenshots or recordings containing real Codex content.
