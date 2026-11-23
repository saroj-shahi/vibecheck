#!/bin/sh
# Claude Code hook -> VibeCheck. Reads the hook event JSON on stdin and writes
# ~/.config/vibecheck/hooks/claude-code.json (atomically). No dependencies.
#
#   Notification                      -> needs_input
#   Stop                              -> done
#   UserPromptSubmit, PreToolUse      -> active
#
# Wire it in ~/.claude/settings.json (adjust the path):
#
#   {
#     "hooks": {
#       "Notification":     [{ "hooks": [{ "type": "command", "command": "~/path/to/claude-code.sh" }] }],
#       "Stop":             [{ "hooks": [{ "type": "command", "command": "~/path/to/claude-code.sh" }] }],
#       "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/path/to/claude-code.sh" }] }],
#       "PreToolUse":       [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/path/to/claude-code.sh" }] }]
#     }
#   }
input=$(cat 2>/dev/null || true)

# Pull a top-level string field out of the event JSON without a JSON parser (good enough for these names).
field() { printf '%s' "$input" | tr -d '\n' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1; }

event=$(field hook_event_name)
case $event in
  Notification)                  state=needs_input; value="needs you"; icon="hand.raised.fill"; ttl=3600 ;;
  Stop)                          state=done;        value="done";      icon="checkmark.circle.fill"; ttl=600 ;;
  UserPromptSubmit|PreToolUse)   state=active;      value="working";   icon="bolt.fill"; ttl=120 ;;
  *) exit 0 ;;
esac

cwd=$(field cwd)
project=$(basename "${cwd:-Claude Code}" | tr -d '"\\' | tr -d '\000-\037')
label="Claude ${project}"

dir=${HOME}/.config/vibecheck/hooks
mkdir -p "$dir"
tmp=$(mktemp "$dir/.tmp.XXXXXX")
printf '{"id":"claude-code","label":"%s","value":"%s","state":"%s","icon":"%s","updatedAt":"%s","ttlSeconds":%s}\n' \
  "$label" "$value" "$state" "$icon" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ttl" > "$tmp"
mv "$tmp" "$dir/claude-code.json"
exit 0
