#!/usr/bin/env python3
"""Linux desktop notifications for Claude Code hooks (Stop and Notification events).

Reads the hook input JSON on stdin:  python3 notify.py < hook-input.json

Environment variables (all optional):
  CLAUDE_NOTIFY_SOUND_DONE   sound when a response finishes (default "complete", "none" for silent)
  CLAUDE_NOTIFY_SOUND_INPUT  sound when input is needed (default "message-new-instant", "none" for silent)
  CLAUDE_NOTIFY_ON_DONE      set to 0 to skip "finished" notifications
  CLAUDE_NOTIFY_DRY_RUN      set to 1 to print "title|subtitle|message|sound" instead of notifying

Sounds are names from the freedesktop sound theme (/usr/share/sounds/freedesktop/stereo).
"""

import json
import os
import shutil
import subprocess
import sys

APP_NAME = "Claude Code"
SOUND_DIRS = ["/usr/share/sounds/freedesktop/stereo", "/usr/local/share/sounds/freedesktop/stereo"]


def parse(text):
    try:
        value = json.loads(text)
    except ValueError:
        return {}
    return value if isinstance(value, dict) else {}


def project_name(cwd):
    if not isinstance(cwd, str):
        return ""
    parts = [part for part in cwd.split("/") if part]
    return parts[-1] if parts else ""


def conversation_title(transcript_path):
    """The transcript format is internal to Claude Code, so any failure here just
    means no conversation title. A /rename title wins over the generated one."""
    if not isinstance(transcript_path, str) or not transcript_path:
        return ""
    custom = generated = ""
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as transcript:
            for line in transcript:
                if '-title"' not in line:
                    continue
                entry = parse(line)
                if entry.get("type") == "custom-title" and entry.get("customTitle"):
                    custom = entry["customTitle"]
                if entry.get("type") == "ai-title" and entry.get("aiTitle"):
                    generated = entry["aiTitle"]
    except OSError:
        return ""
    return custom or generated


def sound_setting(name, fallback):
    value = os.environ.get(name, "")
    if not value:
        return fallback
    return "" if value.lower() == "none" else value


def describe(hook):
    message = hook.get("message") if isinstance(hook.get("message"), str) else ""
    if hook.get("hook_event_name") == "Stop":
        return "done", "✅ Finished — ready for your next message"
    kind = hook.get("notification_type")
    if kind == "permission_prompt":
        # Claude Code reports its own questions as a permission prompt for AskUserQuestion.
        if "AskUserQuestion" in message:
            return "input", "❓ Has a question for you"
        return "input", "🔐 " + message
    if kind == "idle_prompt":
        return "input", "⏳ " + message
    if kind == "elicitation_dialog":
        return "input", "❓ " + message
    return "input", "🔔 " + (message or "Claude Code needs your attention")


def run_quietly(command):
    try:
        return subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def sound_command(name):
    """The command that plays a freedesktop theme sound, or None when no player or sound file
    is found, in which case the notification server is asked to play it instead."""
    if not name:
        return None
    if shutil.which("canberra-gtk-play"):
        return ["canberra-gtk-play", "--id", name]
    for directory in SOUND_DIRS:
        for extension in (".oga", ".ogg", ".wav"):
            path = os.path.join(directory, name + extension)
            if os.path.isfile(path):
                for player in ("pw-play", "paplay"):
                    if shutil.which(player):
                        return [player, path]
    return None


def markup_escape(text):
    # Most notification servers render the body as simple markup.
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def gvariant_string(text):
    # GVariant text format accepts JSON-style double-quoted strings.
    return json.dumps(text, ensure_ascii=False)


def show(title, body, sound, plays_own_sound):
    if plays_own_sound:
        hint_type, hint_name, hint_value = "boolean", "suppress-sound", "true"
    elif sound:
        hint_type, hint_name, hint_value = "string", "sound-name", sound
    else:
        hint_type = None

    if shutil.which("notify-send"):
        command = ["notify-send", "--app-name=" + APP_NAME]
        if hint_type:
            command.append("--hint={}:{}:{}".format(hint_type, hint_name, hint_value))
        return run_quietly(command + ["--", title, body])

    if shutil.which("gdbus"):
        hints = "{}"
        if hint_type == "boolean":
            hints = "{'suppress-sound': <true>}"
        elif hint_type == "string":
            hints = "{'sound-name': <%s>}" % gvariant_string(hint_value)
        return run_quietly([
            "gdbus", "call", "--session",
            "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications",
            "--method", "org.freedesktop.Notifications.Notify",
            # Without "--", gdbus reads the trailing -1 (default timeout) as an option.
            "--", gvariant_string(APP_NAME), "0", '""',
            gvariant_string(title), gvariant_string(body),
            "[]", hints, "-1",
        ])
    return False


def main():
    hook = parse(sys.stdin.read())
    kind, text = describe(hook)
    if kind == "done" and os.environ.get("CLAUDE_NOTIFY_ON_DONE") == "0":
        return

    project = project_name(hook.get("cwd"))
    conversation = conversation_title(hook.get("transcript_path"))
    title = APP_NAME + " · " + project if project else APP_NAME
    subtitle = "Conversation: " + conversation if conversation else ""
    if kind == "done":
        sound = sound_setting("CLAUDE_NOTIFY_SOUND_DONE", "complete")
    else:
        sound = sound_setting("CLAUDE_NOTIFY_SOUND_INPUT", "message-new-instant")

    if os.environ.get("CLAUDE_NOTIFY_DRY_RUN") == "1":
        print("|".join([title, subtitle, text, sound]))
        return

    # Linux notifications have a title and a body but no subtitle line.
    body = markup_escape(subtitle + "\n" + text if subtitle else text)
    player = sound_command(sound)
    show(title, body, sound, player is not None)
    if player:
        run_quietly(player)


if __name__ == "__main__":
    try:
        main()
    except Exception:  # A notification must never break Claude Code's hook run.
        pass
