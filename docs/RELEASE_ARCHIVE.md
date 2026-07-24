# Release Candidate archive drill

Generate and inspect an ephemeral source-package candidate with:

```sh
npm run archive:rc
```

This command uses `npm pack` inside a temporary directory, extracts the resulting archive, validates every entry, records a privacy-safe report, and deletes the archive. It does not publish to npm, GitHub, a Codex marketplace, or any other destination.

The gate requires:

- `package.json` to remain protected from accidental npm publication and the plugin manifest to declare MIT;
- all packaged entries to be tracked by Git;
- required plugin, Hook, Skill, native HUD, server, license, and notice files to be present;
- `.git`, `.power-mode`, dependencies, coverage, logs, local settings, tokens, caches, compiled HUD binaries, credentials, and signing files to be absent;
- personal macOS/Linux paths and private-key material to be absent from text files;
- binary entries to be limited to the documented first-party PNG/GIF files under `docs/media`;
- every included media filename to have provenance in `docs/MEDIA.md` or `docs/DEPENDENCIES.md`;
- the compressed source package to remain below a conservative 2 MB ceiling.

The ignored `.power-mode/archive-rc.json` report contains versions, aggregate entry counts, archive size, SHA-256, and pass/fail facts. It contains no archive path, file list, user path, repository URL, token, task identifier, prompt, code, command, key value, or cursor coordinate. The candidate archive itself is never retained.

Passing this drill means the local source package is clean enough for the public beta. It does not replace real Hook, hands-on interaction, cross-version compatibility, or Instruments validation.
