# Release Candidate security audit

Run the isolated security gate with:

```sh
npm run security:rc
```

The command starts a temporary Power Mode service on a random loopback port and uses a temporary data directory. It does not contact the installed service, alter HUD settings, inject lifecycle activity, or use real task data. The temporary service and token are removed after the run.

The gate verifies:

- the server listener is fixed to `127.0.0.1`;
- the per-installation 256-bit token is stored with owner-only `0600` permissions;
- unauthenticated API access is rejected;
- browser access requires same-origin context and receives a separate stream-only token;
- authenticated cross-origin requests are rejected;
- POST endpoints require JSON, reject malformed bodies, and cap payloads at 1 MB;
- prompt, code, command, credential, token, and related sensitive keys are rejected recursively, including inside nested objects and arrays;
- the user-facing `doctor` report does not expose paths, tokens, or task identifiers;
- rejected requests do not terminate the service.

The ignored report is written to `.power-mode/security-rc.json` with mode `0600`. It contains only pass/fail evidence, platform/runtime versions, and the plugin version—never ports, process IDs, tokens, paths, task IDs, prompts, code, commands, key values, or cursor coordinates.

This automated gate covers the local runtime boundary. Before a public release, the repository owner must still approve a private vulnerability-reporting channel, the license, the supported macOS/Codex range, and repository publication.
