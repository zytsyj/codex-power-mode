# Release Candidate performance baseline

Power Mode includes a reproducible macOS sampler for the native HUD and its local event service:

```sh
npm run perf:rc
```

The command uses synthetic, isolated preview events, restores the real HUD state afterward, and verifies that neither process was replaced during measurement. It samples CPU and resident memory every 500 ms and records macOS `top` POWER score, thread count, and a one-second context-switch delta. The local JSON report is written to `.power-mode/performance-rc.json`, which is ignored by Git.

The sampler does not read or retain prompts, code, key values, commands, cursor coordinates, task identifiers, or personal paths. It probes `xctrace` and records whether full Xcode Instruments is available, but it never substitutes `top` POWER or layer counts for a real GPU/Energy Log trace.

The native HUD also has a deterministic compositor budget self-test:

```sh
CODEX_POWER_MODE_LAYER_BUDGET_SELF_TEST=1 /path/to/codex-power-mode-overlay
```

It overlaps a high-tier Energy breakthrough, semantic transition, Typing Combo, cursor milestone, and prompt injection, then recursively counts live Core Animation layers and animations for Focus, Arcade, and Reduce Motion. macOS CI enforces ceilings of 96 layers and 88 animations. This is a regression guard for accidental layer growth, not a GPU benchmark.

## Initial baseline

Measured on 2026-07-23 with macOS 26.5 (Darwin 25.5.0), Apple silicon (`arm64`), Node.js 22.23.1, Swift 6.3.3, and private plugin build `0.8.0+codex.20260722162831`. The HUD used Arcade, normal intensity, 1.3× scale, and full motion. Values are a single-machine baseline, not yet the final supported macOS range.

| Scenario | Process | CPU mean | CPU p95 | CPU max | RSS max | POWER | Threads | Context switches/s |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Idle, 6 s | HUD | 0.32% | 0.40% | 0.40% | 51.78 MB | 0.2 | 6 | 142 |
| Idle, 6 s | Service | 0.00% | 0.00% | 0.00% | 50.38 MB | 0.0 | 12 | 0 |
| Full lifecycle, 24 s | HUD | 0.65% | 1.30% | 1.40% | 51.83 MB | 0.3 | 6 | 221 |
| Full lifecycle, 24 s | Service | 0.02% | 0.10% | 0.10% | 50.38 MB | 0.0 | 12 | 20 |
| Energy breakthrough, 11 s | HUD | 0.47% | 0.70% | 0.90% | 51.81 MB | 0.3 | 6 | 219 |
| Energy breakthrough, 11 s | Service | 0.03% | 0.10% | 0.30% | 50.38 MB | 0.0 | 12 | 54 |

All automated budgets passed. Current gates are 5%/3% idle CPU p95 and 45%/15% active CPU p95 for HUD/service, 128 MB RSS per process, POWER 5/3 idle and 50/15 active, and 20/30 threads. These are regression ceilings rather than performance targets.

The initial compositor-budget run measured 70 layers/60 animations for Focus, 74/64 for Arcade, and 58/22 for Reduce Motion at the synthetic peak. Reduce Motion is explicitly required to allocate fewer transient layers and animations than Focus.

The full lifecycle scenario covers Typing Combo charge, Observe, Act, Verify, Wait, Recover, Complete, decay, and disconnect choreography. The Energy scenario exercises repeated tier breakthroughs. The initial machine has Command Line Tools but not full Xcode, so `xctrace` is currently unavailable and Instruments-based GPU/energy inspection with Energy Log remains pending. Final RC acceptance also requires repeat measurements across the supported hardware and macOS range.
