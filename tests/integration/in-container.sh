#!/bin/bash
# Runs inside the container, under dbus-run-session. Sends notifications through
# scripts/notify.py and checks what reaches the notification server over D-Bus.
set -u
Xvfb :99 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
dunst >/dev/null 2>&1 &
sleep 1

FIX=/plugin/tests/fixtures
pass=0
fail=0

# deliver <name> <stdin> <expected text...>
deliver() {
  local name="$1" input="$2"
  shift 2
  local log
  log=$(mktemp)
  dbus-monitor "interface='org.freedesktop.Notifications',member='Notify'" >"$log" 2>/dev/null &
  local monitor=$!
  sleep 0.5
  printf '%s' "$input" | python3 /plugin/scripts/notify.py
  sleep 0.5
  kill "$monitor"
  local missing=""
  for expected in "$@"; do
    grep -qF -- "$expected" "$log" || missing="$missing [$expected]"
  done
  if [ -z "$missing" ]; then
    pass=$((pass + 1))
    echo "ok   $name"
  else
    fail=$((fail + 1))
    echo "FAIL $name: missing$missing"
    sed 's/^/     /' "$log"
  fi
}

STOP="{\"hook_event_name\":\"Stop\",\"cwd\":\"/home/me/my-app\",\"transcript_path\":\"$FIX/transcript-ai-title.jsonl\"}"
ASK='{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Run <script> & \"quote\"","cwd":"/home/me/my-app"}'

deliver "notify-send: finished notification" "$STOP" \
  'string "Claude Code"' 'string "Claude Code · my-app"' 'Conversation: Fix login redirect' '✅ Finished' '"sound-name"' 'string "complete"'

deliver "notify-send: markup characters are escaped" "$ASK" \
  'Run &lt;script&gt; &amp; "quote"'

# Hide notify-send so the gdbus fallback is used.
mv /usr/bin/notify-send /usr/bin/notify-send.hidden

deliver "gdbus: finished notification" "$STOP" \
  'string "Claude Code"' 'string "Claude Code · my-app"' 'Conversation: Fix login redirect' '✅ Finished' '"sound-name"' 'string "complete"'

deliver "gdbus: markup characters and quotes survive" "$ASK" \
  'Run &lt;script&gt; &amp; "quote"'

mv /usr/bin/notify-send.hidden /usr/bin/notify-send

# With a sound player and the sound file present, the script plays the sound
# itself and tells the server not to.
mkdir -p /usr/share/sounds/freedesktop/stereo
touch /usr/share/sounds/freedesktop/stereo/complete.oga
printf '#!/bin/sh\necho "$@" > /tmp/played\n' > /usr/local/bin/paplay
chmod +x /usr/local/bin/paplay
deliver "plays the sound itself when it can" "$STOP" '"suppress-sound"' 'boolean true'
grep -q 'complete.oga' /tmp/played 2>/dev/null && { pass=$((pass + 1)); echo "ok   sound file was played"; } \
  || { fail=$((fail + 1)); echo "FAIL sound file was not played"; }

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
