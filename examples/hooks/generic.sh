#!/bin/sh
# Writes a VibeCheck hook file for any tool (Codex, Gemini CLI, a build script...).
# Usage: generic.sh <id> <label> <value> <state> [ttlSeconds]
#   state: active | idle | needs_input | done | error
set -eu
[ $# -ge 4 ] || { echo "usage: $0 <id> <label> <value> <state> [ttlSeconds]" >&2; exit 2; }
id=$1 label=$2 value=$3 state=$4 ttl=${5:-300}
case $state in active|idle|needs_input|done|error) ;; *) echo "bad state: $state" >&2; exit 2;; esac
case $ttl in ''|*[!0-9]*) echo "ttl must be whole seconds" >&2; exit 2;; esac

# Escape backslashes and quotes, and drop control characters, so the JSON stays valid.
esc() { printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

dir=${HOME}/.config/vibecheck/hooks
mkdir -p "$dir"
# File name from the id, letters, digits, dot, dash, underscore only.
name=$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')
tmp=$(mktemp "$dir/.tmp.XXXXXX")
printf '{"id":"%s","label":"%s","value":"%s","state":"%s","updatedAt":"%s","ttlSeconds":%s}\n' \
  "$(esc "$id")" "$(esc "$label")" "$(esc "$value")" "$state" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ttl" > "$tmp"
mv "$tmp" "$dir/$name.json"
