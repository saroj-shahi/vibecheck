# Vibe Hooks

Any tool can show a pill on the VibeCheck deck by writing a small JSON file. VibeCheck only reads these
files. It never creates, edits or deletes them, and it doesn't create the folder either.

Folder: `~/.config/vibecheck/hooks/` (create it yourself; the example scripts do).

Limits: `*.json` files only, at most 8 files, at most 4 KB each, symlinks are ignored. Anything
that doesn't parse is skipped silently.

```json
{
  "id": "claude-code",
  "label": "Claude vibecheck",
  "value": "needs you",
  "state": "needs_input",
  "icon": "hand.raised.fill",
  "updatedAt": "2026-01-31T09:30:00Z",
  "ttlSeconds": 300
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Non-empty string |
| `label` | yes | Cut to 24 characters |
| `value` | yes | Cut to 32 characters |
| `state` | yes | `active`, `idle`, `needs_input`, `done` or `error` |
| `updatedAt` | yes | ISO 8601 (`2026-01-31T09:30:00Z`) |
| `icon` | no | An SF Symbol name; unknown names show a dot |
| `ttlSeconds` | no | The pill disappears when `updatedAt + ttlSeconds` has passed. Default 300, clamped to 5 s ... 24 h |

Pills sort needs_input first, then error, then active, then the rest. Up to 3 show, plus a "+N" pill.
`needs_input` is orange and `error` is red. With "Pulse the ring when an agent needs you" on
(Settings > Menu Bar), the menu bar ring pulses while any live hook is `needs_input`.

Write files atomically (temp file in the same folder, then `mv`) so VibeCheck never reads half a file.

## Scripts

- `claude-code.sh`: for Claude Code hooks. Notification means needs_input, Stop means done,
  UserPromptSubmit and PreToolUse mean active. The `settings.json` snippet is at the top of the script.
- `generic.sh <id> <label> <value> <state> [ttl]`: for Codex, Gemini CLI or anything else.
  Example: `./generic.sh codex "Codex" "running tests" active 120`
