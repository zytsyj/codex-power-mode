# Release Candidate stability checks

Power Mode keeps deterministic state tests separate from a small real-process recovery check.

## Automated coverage

`npm run check` verifies session arbitration and storage behavior for Focus, Global, and Mix; late-event suppression; per-session Energy and Combo isolation; Mix parallel-stop and recovery handling; missing terminal-event fallback to Idle; service authentication; clean SSE shutdown; stale PID safety; and concurrent native startup locking.

The isolated tests use temporary data directories and synthetic lifecycle metadata. They do not connect to or mutate a real Codex task.

## Real service recovery

Run this only while one installed Power Mode service and native HUD are healthy:

```sh
npm run stability:rc
```

The command validates the exact running service identity, stops only that service, leaves the native HUD alive long enough to enter reconnecting state, restarts the same installed build, and waits for its authenticated event stream to reconnect. It then issues eight concurrent native-start requests and confirms:

- the original HUD process was reused;
- exactly one service and one HUD remain;
- the event stream reconnected;
- the data directory stayed consistent;
- all display settings were preserved.

The ignored report at `.power-mode/stability-rc.json` contains only pass/fail facts, timing, version, and process counts. It excludes task identifiers, prompts, code, commands, key values, cursor coordinates, authentication tokens, and local paths.

## Initial recovery result

The first single-machine run on macOS 26.5 passed: the service restarted, the original HUD survived and reconnected, eight concurrent native-start requests reused that HUD, and the final doctor check found one service, one HUD, preserved settings, and one consistent data directory. This is an RC recovery baseline, not a claim of compatibility with every supported macOS or Codex version.

This check briefly interrupts live visual updates. It does not stop Codex, erase Power Mode history, change settings, inject lifecycle events, or modify the connected task. Final RC acceptance still requires a longer personal-use period and compatibility checks for supported macOS/Codex versions, display arrangements, and inactive-app policies.
