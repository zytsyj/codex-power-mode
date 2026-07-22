# Media provenance

The checked-in preview images are first-party frames rendered directly from the native Core Animation implementation. They contain synthetic state only: no Codex window, prompt, source code, user name, local path, cursor coordinate, or runtime history.

## Reproduce the QA set

On macOS with the system Swift toolchain:

```bash
npm run render:qa
```

This compiles a temporary native renderer and writes the complete 234-frame matrix to the ignored `.power-mode/render-qa` directory. The matrix covers light/dark, Focus/Arcade/Reduce Motion, all seven Energy tiers, six semantic states at low/mid/high Energy, four completion outcomes, high-tier transitions, cursor effects, and Typing Combo colors.

The five images under `docs/media/` are selected unchanged from that generated matrix:

- `focus-light-verify.png`
- `arcade-dark-act.png`
- `arcade-dark-complete.png`
- `typing-combo-dark.png`
- `reduced-light-recover.png`

Regenerate and visually inspect the matrix after any native visual change. Do not replace these files with screenshots containing real Codex content.
