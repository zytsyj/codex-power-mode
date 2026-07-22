# Privacy

Codex Power Mode is local-only and has no analytics or telemetry.

## Data retained

- Semantic lifecycle type and timestamp.
- Desktop conversation identifier and source classification.
- Energy, Combo, verification outcome, risk, confidence, and aggregate edit counts.
- Display settings, saved HUD position, and historical best values.
- A private local service token used only for loopback authentication.

## Data not retained

- User prompts or assistant responses.
- Source-code or patch contents.
- Typed characters, key values, clipboard contents, or input-field contents.
- Command text, environment secrets, authentication credentials, or remote URLs from Codex activity.
- Cursor coordinates in diagnostics or persisted state.

## macOS permissions

Typing Combo is optional. When enabled, macOS Accessibility permission is used only to locate the active Codex insertion point for cursor-local effects. A listen-only event tap counts eligible typing rhythm while Codex is foreground; deletion, navigation, Enter, and command/control shortcuts do not increase the count. Disabling Typing Combo removes the need for Accessibility permission.

## Network behavior

The event service listens only on the loopback interface. Hooks, diagnostics, previews, and the native overlay authenticate locally. Browser preview access is same-origin and uses a process-scoped stream-only token. No runtime data is sent to the project author or a third-party service.

## Deletion

`npm run purge:data -- --yes` stops Power Mode and deletes its recognized local data directory, including settings, history, and the local token. It refuses broad or unrelated paths. Removing the plugin package is a separate Codex operation.
