# Release Candidate compatibility matrix

Compatibility acceptance is split into automated renderer coverage, real local health checks, and explicit hands-on checks. Synthetic preview data is never presented as proof that real Codex lifecycle hooks or prompt submission worked.

## Reproducible automated matrix

Run on macOS:

```sh
npm run compatibility:rc
```

The command regenerates all 326 native frames and verifies PNG integrity plus coverage for:

- light and dark appearances;
- Focus, Arcade, Classic, and Reduce Motion;
- Observe, Act, Verify, Wait, Recover, and Complete;
- all five Energy tiers and four completion outcomes;
- all thirteen cursor styles plus meme-word and milestone samples;
- cyan, violet, pink, and gold Typing Combo palettes;
- light/dark Classic Power Mode with a centered Typing Combo and no orb.

It also records aggregate installed-service health, HUD connection, Accessibility permission, and single-instance results. The ignored JSON report contains no task identifiers, prompt or code contents, commands, key values, cursor coordinates, tokens, or local paths.

## Evidence status

| Area | Automated evidence | Hands-on evidence still required |
| --- | --- | --- |
| Theme and motion | 326 native light/dark Focus/Arcade/Classic/Reduce Motion frames | Observe transition rhythm and legibility on the target displays |
| Semantic and Energy states | Six states, five tiers, four completion outcomes | Real lifecycle ordering from a trusted Codex desktop task |
| Typing feedback | Static Spark/Neon and Combo palette frames; Accessibility health | Effects following the real insertion point; real `UserPromptSubmit` injection |
| Floating behavior | Direct-drag hit-target/click-through tests plus isolated position save, reload, and reset | Drag gesture, multiple-display attach/detach, Dock and visible-frame changes |
| Foreground and idle policy | Isolated save/reload coverage for hide/stay and hide/quiet-orb settings | Policy timing and behavior in the live app |
| Language | English/Chinese strings compile; automatic/English/Chinese preference persistence | English, Chinese, and automatic selection reviewed in the live menu/HUD |
| Lifecycle maintenance | Isolated install/upgrade and real service-reconnect checks | Clean install, upgrade, stop, permission revocation, and uninstall on the final support range |

## Recoverable hands-on session

Start a local acceptance checkpoint before changing menu settings:

```sh
npm run acceptance:interaction -- begin
```

Record only a predefined observation, for example `npm run acceptance:interaction -- record cursor-spark passed`, and inspect progress with `npm run acceptance:interaction -- status`. The report accepts no free-form notes and stays in Power Mode's private persistent plugin-data directory, never the repository or versioned plugin cache. Finish with `npm run acceptance:interaction -- restore`; it atomically restores the exact baseline display settings and restarts only the native HUD. Starting a session never marks an item passed automatically.

## Current limitation

The first matrix was generated on Apple silicon with macOS 26.5. It proves renderer coverage and the current machine's local health, not the final supported macOS, hardware, display, or Codex version range. Those ranges remain intentionally undocumented until hands-on RC testing is complete.

The native settings self-test always uses a temporary configuration path. It verifies atomic save/reload, value validation, scale clamping, position persistence/reset, and the main interaction policies without reading or changing the installed user's settings.
