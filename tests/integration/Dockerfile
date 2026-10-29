FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 dbus dbus-x11 xvfb dunst libnotify-bin libglib2.0-bin \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /plugin
