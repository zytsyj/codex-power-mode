# Release Candidate compatibility matrix

Compatibility acceptance is split into automated renderer coverage, real local health checks, and explicit hands-on checks. Synthetic preview data is never presented as proof that real Codex lifecycle hooks or prompt submission worked.

## Reproducible automated matrix

Run on macOS:

```sh
npm run compatibility:rc
```

The command regenerates all 234 native frames and verifies PNG integrity plus coverage for:

- light and dark appearances;
- Focus, Arcade, and Reduce Motion;
- Observe, Act, Verify, Wait, Recover, and Complete;
- all seven Energy tiers and four completion outcomes;
- Spark, Neon, and Neon milestone cursor samples;
- cyan, violet, pink, and gold Typing Combo palettes.

It also records aggregate installed-service health, HUD connection, Accessibility permission, and single-instance results. The ignored JSON report contains no task identifiers, prompt or code contents, commands, key values, cursor coordinates, tokens, or local paths.

## Evidence status

| Area | Automated evidence | Hands-on evidence still required |
| --- | --- | --- |
| Theme and motion | 234 native light/dark Focus/Arcade/Reduce Motion frames | Observe transition rhythm and legibility on the target displays |
| Semantic and Energy states | Six states, seven tiers, four completion outcomes | Real lifecycle ordering from a trusted Codex desktop task |
| Typing feedback | Static Spark/Neon and Combo palette frames; Accessibility health | Effects following the real insertion point; real `UserPromptSubmit` injection |
| Floating behavior | Position/config/state logic tests | Drag, restart persistence, multiple-display attach/detach, Dock and visible-frame changes |
| Foreground and idle policy | Configuration normalization and presentation tests | Hide/stay/follow policies plus hide/quiet-orb timing in the live app |
| Language | English/Chinese strings and menu paths compile | English, Chinese, and automatic selection reviewed in the live menu/HUD |
| Lifecycle maintenance | Isolated install/upgrade and real service-reconnect checks | Clean install, upgrade, stop, permission revocation, and uninstall on the final support range |

## Current limitation

The first matrix was generated on Apple silicon with macOS 26.5. It proves renderer coverage and the current machine's local health, not the final supported macOS, hardware, display, or Codex version range. Those ranges remain intentionally undocumented until hands-on RC testing is complete.
