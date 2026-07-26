# Media provenance

The repository contains two clearly separated media sets:

1. deterministic first-party QA frames rendered directly from the native Core Animation implementation; and
2. real macOS screen recordings made specifically for the public README.

The checked-in media contains no Codex window, prompt, source code, user name, local path, cursor coordinate, or runtime history.

`hero.svg` is a first-party, hand-authored vector composition derived from the same semantic palette and connected-machine geometry. It presents the current Focus, Arcade, and no-orb Classic Power Mode alongside the five-tier Energy evolution. It contains no external assets, embedded fonts, scripts, user data, or runtime content.

## Real README recordings

Files prefixed with `real-` and the GIFs in `docs/media/cursor-gallery/` are screen recordings of the native HUD running beside a blank Codex desktop task. They were captured with:

- a temporary isolated service and data directory, separate from the normal Power Mode installation;
- synthetic semantic events for Energy, agent states, Agent Combo, disconnect, and completion outcomes;
- temporary repeated `a` input in an otherwise empty composer for Typing Combo, input injection, and cursor effects;
- a fixed crop that excludes the sidebar, task history, output panel, and any personal content.

The temporary draft was cleared after every cursor recording. The isolated service and full-screen positioning screenshots were deleted after capture. The normal Power Mode service was restored before the media was checked in.

README overview recordings:

- `real-energy-evolution.gif`
- `real-agent-states.gif`
- `real-agent-combo.gif`
- `real-typing-combo.gif`
- `real-typing-injection.gif`
- `real-completion-outcomes.gif`
- `real-cursor-geometric.gif`
- `real-cursor-memes.gif`

The thirteen files in `cursor-gallery/` are the corresponding individual cursor-effect recordings. The legacy meme images visible in four of those recordings retain the separate rights status described in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

## Static README gallery

The six PNG files in `docs/media/static-gallery/` are editorial layouts composed only from stable frames of the real README recordings above:

- `energy-evolution.png`
- `semantic-states.png`
- `combos-and-injection.png`
- `completion-outcomes.png`
- `cursor-geometric.png`
- `cursor-memes.png`

They add project-authored headings, captions, dark panels, and spacing around the unchanged captured HUD frames. The semantic-state layout deliberately uses the transient full editing arrow, while the Combo layout uses a frame where the Typing charge trail is visibly entering the orb. These static summaries follow the same privacy boundary as the source recordings and contain no additional runtime data.

The matching `*-en.png` files form a separate English README set. They are composed from deterministic native QA renders rather than the Chinese screen recordings, so both the editorial text and the HUD's internal labels remain English. The English injection panel combines the project-rendered English orb with a project-authored dotted charge path; it does not depict external or personal data.

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

Seven compact animated storyboards are composed from the same synthetic frames with macOS ImageIO:

- `focus-demo.gif` — Observe → Act → Verify → Complete.
- `arcade-demo.gif` — cursor/Typing Combo → Observe → Act → Energy breakthrough → Verify → Complete.
- `energy-demo.gif` — Wake → Charge → Drive → Critical → Peak.
- `completion-demo.gif` — verified → unverified → cancelled → no-change.
- `cursor-power-demo.gif` — spark → orbit → ripple → prism → neon milestone.
- `cursor-chaos-demo.gif` — wormhole → glitch → tentacle → 典 → 赢.
- `cursor-meme-demo.gif` — Hands-behind Possum → Fresh Cat → Knife-shield Dog → Elegant Person.

Rebuild the GIFs in the ignored `.power-mode/render-demos` directory with:

```bash
npm run render:demos
```

These seven legacy GIFs are deliberately small animated summaries, not recordings of a real Codex window and not frame-perfect captures of every transient particle. They remain checked in as deterministic visual references even though the README now leads with the real recordings.

Regenerate and visually inspect the matrix and demos after any native visual change. Never check in screenshots or recordings containing real Codex content.
