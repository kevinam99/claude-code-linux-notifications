---
description: Turn notification sounds on or off, change them, or test them
argument-hint: "[on | off | test | done <sound> | input <sound>]"
---

Change the notification sounds of the linux-notifications plugin. Arguments: `$ARGUMENTS`

The plugin reads two environment variables from the `env` section of `~/.claude/settings.json`:

- `CLAUDE_NOTIFY_SOUND_DONE`: sound when a response finishes (default `complete`)
- `CLAUDE_NOTIFY_SOUND_INPUT`: sound when Claude needs input (default `message-new-instant`)

`none` means silent. When a variable isn't set, the default applies. Changes take effect from the next notification, with no restart.

Do what the arguments ask:

- **No arguments:** show both current sounds (say "default (complete)" or "default (message-new-instant)" when unset), list the available sounds, and show the usage line from this command's argument hint. Change nothing.
- **`off`:** set both variables to `none`.
- **`on`:** remove both variables, so the defaults apply again.
- **`test`:** change nothing, and send one test notification with each current sound, as described below. Read the current values from the settings file rather than this session's environment, and use the default for an unset one. Skip a sound that is `none` and say it's off.
- **`done <sound>`** or **`input <sound>`:** set that one variable. `<sound>` can be `off` (store `none`), `default` (remove the variable), or a sound name.
- **Anything else:** show the usage line and change nothing.

Sound names are the files in `/usr/share/sounds/freedesktop/stereo` or `/usr/local/share/sounds/freedesktop/stereo` without the extension, such as `bell` or `dialog-warning`. If no file matches, list the available sounds and change nothing. If neither folder exists, accept the name, but say it couldn't be checked and that the freedesktop sound theme (often the `sound-theme-freedesktop` package) may not be installed.

Edit `~/.claude/settings.json` so that only these two variables change: keep every other setting and every other `env` entry. If the file or the `env` section doesn't exist, create it. Leave an empty `env` section out rather than writing `"env": {}`.

After a change, send a test notification for each sound that changed, passing the new value explicitly, because this session may not have reloaded its settings yet. For example, for `done bell`:

```
echo '{"hook_event_name":"Stop","cwd":"'"$PWD"'"}' | CLAUDE_NOTIFY_SOUND_DONE=bell python3 "${CLAUDE_PLUGIN_ROOT}/scripts/notify.py"
```

For an input sound, use `CLAUDE_NOTIFY_SOUND_INPUT` and the input `{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input","cwd":"'"$PWD"'"}`. If the Bash tool runs in a sandbox, run this outside it: a sandbox can block access to the desktop's notification service. Skip the test when the sound was turned off.

Finish with one short line saying what changed.
