# Troubleshooting

Start with `npm run doctor` from the matching source checkout or the installed plugin's `doctor` command.

## HUD is not visible

- Confirm the local service and native HUD are running.
- Check the idle behavior and the **When Codex is inactive** setting.
- Bring Codex to the foreground and start a trusted desktop task.
- Use the menu-bar bolt to reset the saved position, especially after display changes.

## Hooks are waiting

The service can be healthy before it receives a trusted lifecycle event. Open a new Codex task, review and trust the plugin hooks, then send a request that causes real Codex activity. A waiting notice alone is not a service failure.

## Typing Combo works but cursor effects do not

Grant Accessibility permission to the installed overlay, restart Power Mode, focus the Codex message field, and run `doctor` again. Deletion, navigation, Enter, and command/control shortcuts intentionally do not increase Typing Combo.

## Version mismatch or duplicate HUD

Stop Power Mode, reinstall the plugin once from the configured marketplace, and start a new Codex task. Run `doctor` and confirm that the installed and running versions match and instance counts are one. Avoid starting scripts from multiple cached plugin versions.

## Safe recovery

Use `npm run reset:settings -- --yes` for display or position problems. It preserves history. Use `npm run purge:data -- --yes` only when a full local reset is intended; it removes settings, history, and authentication data. Neither command publishes, updates, or changes repository visibility.
