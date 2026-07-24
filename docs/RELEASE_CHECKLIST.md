# Public beta release checklist

Power Mode `0.9.0` is prepared as an open-source public beta. Source publication and production-grade signed binary distribution are separate milestones.

## Open-source decisions

- [x] License source code, documentation, and project-authored media under MIT.
- [x] Exclude the four legacy meme image sets from MIT and document their separate status.
- [x] Use GitHub private vulnerability reporting.
- [x] Publish repository and install metadata for `zytsyj/codex-power-mode`.
- [x] Use `0.9.0` as the first public-beta version.
- [x] Pin GitHub Actions to immutable commit SHAs.
- [x] Provide issue forms, a pull-request template, contribution guidance, and a code of conduct.

## Automated engineering gates

- [x] Validate the plugin manifest, public marketplace entry, Hook configuration, and release hygiene.
- [x] Run the complete Node test suite and macOS Swift compilation.
- [x] Verify loopback binding, token permissions, authentication, browser-token scope, origin validation, payload limits, recursive sensitive-field rejection, failure isolation, and diagnostic redaction.
- [x] Verify native reconnect policy, settings persistence, single-instance startup, and bounded compositor layers/animations.
- [x] Generate the deterministic native compatibility matrix and privacy-safe project media.
- [x] Produce a tracked-only source archive with no runtime state, binaries, logs, secrets, or personal paths.

## Public-beta follow-up validation

These items improve the supported compatibility claim but do not prevent publishing the source as a beta:

- [ ] Repeat clean install, upgrade, purge, removal, and Accessibility revocation on a separate macOS account.
- [ ] Repeat CPU, GPU, and Energy Log sampling across the supported macOS range.
- [ ] Expand hands-on testing with concurrent Focus, Global, and Mix tasks.
- [ ] Ship a Developer ID-signed and notarized precompiled app before describing installation as zero-toolchain or upgrade authorization as seamless.
- [ ] Replace or obtain explicit redistribution permission for the four legacy meme image sets before describing the entire asset bundle as MIT/open-source.
