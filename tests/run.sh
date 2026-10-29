#!/bin/bash
# Runs scripts/notify.py in dry-run mode against sample hook inputs and checks
# the notification it would show. Usage: tests/run.sh
set -u
cd "$(dirname "$0")/.."
FIX="$PWD/tests/fixtures"
pass=0
fail=0

# check <name> <expected "title|subtitle|message|sound"> <stdin> [VAR=value ...]
check() {
  local name="$1" expected="$2" input="$3"
  shift 3
  local actual
  actual=$(printf '%s' "$input" | env CLAUDE_NOTIFY_DRY_RUN=1 "$@" python3 scripts/notify.py 2>&1)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
    echo "ok   $name"
  else
    fail=$((fail + 1))
    echo "FAIL $name"
    echo "     expected: $expected"
    echo "     actual:   $actual"
  fi
}

check "stop uses the auto-generated conversation title" \
  "Claude Code · my-app|Conversation: Fix login redirect|✅ Finished — ready for your next message|complete" \
  "{\"hook_event_name\":\"Stop\",\"cwd\":\"/Users/x/code/my-app\",\"transcript_path\":\"$FIX/transcript-ai-title.jsonl\"}"

check "a /rename title wins over the auto-generated one" \
  "Claude Code · my-app|Conversation: Auth bugfix|✅ Finished — ready for your next message|complete" \
  "{\"hook_event_name\":\"Stop\",\"cwd\":\"/Users/x/code/my-app\",\"transcript_path\":\"$FIX/transcript-custom-title.jsonl\"}"

check "no title in transcript leaves the subtitle empty" \
  "Claude Code · my-app||✅ Finished — ready for your next message|complete" \
  "{\"hook_event_name\":\"Stop\",\"cwd\":\"/Users/x/code/my-app\",\"transcript_path\":\"$FIX/transcript-no-title.jsonl\"}"

check "missing transcript file leaves the subtitle empty" \
  "Claude Code · my-app||✅ Finished — ready for your next message|complete" \
  '{"hook_event_name":"Stop","cwd":"/Users/x/code/my-app","transcript_path":"/nonexistent/x.jsonl"}'

check "a question is reworded" \
  "Claude Code · my-app||❓ Has a question for you|message-new-instant" \
  '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use AskUserQuestion","cwd":"/Users/x/code/my-app"}'

check "a tool permission keeps Claude Code's message" \
  "Claude Code · my-app||🔐 Claude needs your permission to use Bash|message-new-instant" \
  '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","cwd":"/Users/x/code/my-app"}'

check "idle prompt" \
  "Claude Code · my-app||⏳ Claude is waiting for your input|message-new-instant" \
  '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input","cwd":"/Users/x/code/my-app"}'

check "MCP elicitation dialog" \
  "Claude Code · my-app||❓ An MCP server needs your input|message-new-instant" \
  '{"hook_event_name":"Notification","notification_type":"elicitation_dialog","message":"An MCP server needs your input","cwd":"/Users/x/code/my-app"}'

check "quotes and backslashes in the message pass through untouched" \
  "Claude Code · my-app||🔐 Allow \"rm -rf\" in C:\\tmp's dir?|message-new-instant" \
  '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow \"rm -rf\" in C:\\tmp'"'"'s dir?","cwd":"/Users/x/code/my-app"}'

check "unknown notification type falls back to its message" \
  "Claude Code · my-app||🔔 Something else happened|message-new-instant" \
  '{"hook_event_name":"Notification","notification_type":"something_new","message":"Something else happened","cwd":"/Users/x/code/my-app"}'

check "missing cwd shows plain Claude Code" \
  "Claude Code||✅ Finished — ready for your next message|complete" \
  '{"hook_event_name":"Stop"}'

check "invalid JSON still notifies" \
  "Claude Code||🔔 Claude Code needs your attention|message-new-instant" \
  'this is not json'

check "empty input still notifies" \
  "Claude Code||🔔 Claude Code needs your attention|message-new-instant" \
  ''

check "sounds can be overridden" \
  "Claude Code · my-app||✅ Finished — ready for your next message|bell" \
  '{"hook_event_name":"Stop","cwd":"/Users/x/code/my-app"}' \
  CLAUDE_NOTIFY_SOUND_DONE=bell

check "input sound can be overridden" \
  "Claude Code · my-app||🔐 Claude needs your permission to use Bash|dialog-warning" \
  '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","cwd":"/Users/x/code/my-app"}' \
  CLAUDE_NOTIFY_SOUND_INPUT=dialog-warning

check "sound can be turned off" \
  "Claude Code · my-app||✅ Finished — ready for your next message|" \
  '{"hook_event_name":"Stop","cwd":"/Users/x/code/my-app"}' \
  CLAUDE_NOTIFY_SOUND_DONE=none

check "finished notifications can be turned off" \
  "" \
  '{"hook_event_name":"Stop","cwd":"/Users/x/code/my-app"}' \
  CLAUDE_NOTIFY_ON_DONE=0

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
