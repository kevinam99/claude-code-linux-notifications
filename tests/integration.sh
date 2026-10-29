#!/bin/bash
# Builds a Debian container with a real notification server (dunst on Xvfb) and
# checks what scripts/notify.py delivers over D-Bus. Needs Docker.
set -eu
cd "$(dirname "$0")/.."
docker build -q -t claude-code-linux-notifications-test tests/integration >/dev/null
docker run --rm -v "$PWD":/plugin:ro claude-code-linux-notifications-test \
  dbus-run-session -- bash /plugin/tests/integration/in-container.sh
