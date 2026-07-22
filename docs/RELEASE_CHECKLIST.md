# Public release checklist

The repository must remain private until the owner explicitly authorizes publication.

## Blocking decisions

- [ ] Choose and approve an open-source license; the project is currently `UNLICENSED` and all rights are reserved.
- [ ] Choose a private security-reporting channel suitable for the public repository.
- [ ] Approve the public repository visibility change and first release version.

## Product acceptance

- [ ] Complete a stable personal-use period with no unresolved high-severity defects.
- [ ] Confirm Focus, Global, and Mix with concurrent desktop tasks.
- [ ] Confirm Typing Combo, cursor effects, real prompt submission injection, decay, and disconnect behavior.
- [ ] Confirm light/dark, Focus/Arcade, and Reduce Motion rendering.
- [ ] Confirm idle hide/orb, dragging, display changes, and inactive-app policies.

## Engineering acceptance

- [ ] Run `npm run check`, plugin validation, skill validation, and macOS Swift compilation.
- [ ] Reconfirm `docs/DEPENDENCIES.md`, upstream CI-action licenses, and `THIRD_PARTY_NOTICES.md`; document every newly bundled dependency or asset.
- [ ] Decide whether public CI actions must be pinned to immutable commit SHAs.
- [ ] Run `npm run doctor` after a fresh install and an upgrade.
- [x] Run `npm run stability:rc` and review the service-restart, HUD-reconnect, concurrent-start, settings, and single-instance results on the initial RC machine.
- [x] Generate and validate the 234-frame native compatibility matrix with `npm run compatibility:rc` on the initial RC machine.
- [ ] Verify the full [installation and maintenance](INSTALLATION.md) flow on a clean account, including start/stop, settings reset, data purge, package removal, and Accessibility revocation.
- [ ] Verify loopback binding, authentication, origin validation, payload limits, and diagnostic redaction.
- [x] Record an initial reproducible single-machine CPU, memory, POWER, thread, and wakeup baseline for idle and synthetic bursts.
- [ ] Repeat performance sampling across the supported macOS range and inspect per-process GPU/energy behavior with Instruments.
- [ ] Confirm the release archive contains no runtime state, compiled local binary, logs, secrets, personal paths, or private-repository metadata.

## Documentation and media

- [x] Capture current privacy-safe light/dark screenshots for Focus, Arcade, Typing Combo, and Reduce Motion.
- [x] Generate short privacy-safe Focus/Arcade animated storyboards from synthetic native frames.
- [ ] Review README, installation, architecture, privacy, security, troubleshooting, contribution, and maintenance documentation.
- [ ] Add supported macOS and Codex version ranges after final compatibility testing.
- [ ] Prepare release notes and a known-limitations section.
