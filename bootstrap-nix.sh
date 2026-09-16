#!/bin/sh
# One-time Nix bootstrap into the persisted /nix dataset.
#
# Nix cannot be baked into the image: /nix is a bind mount at runtime, so an
# image-installed store would be shadowed by the (empty) dataset the moment the
# container starts. Installing here instead means the store persists across
# recreates and only ever runs once.
#
# This must NEVER be fatal. A network blip on a Monday morning should not stop
# opencode from starting — agents lose `nix` until the next start, not the whole
# environment. Hence the unconditional exit 0.
set -u

if [ -d /nix/store ] && [ -e /nix/var/nix/profiles/default ]; then
  echo "[nix] store already present — skipping bootstrap"
  exit 0
fi

echo "[nix] bootstrapping single-user install into /nix (one time) ..."
chown opencoded:opencoded /nix 2>/dev/null || true

# --no-daemon: single-user, no systemd in a container.
# --no-modify-profile: the shell profile lives in a non-persisted home dir;
#   PATH is set in the image instead so it survives recreates.
su opencoded -s /bin/sh -c \
  'curl -fsSL https://nixos.org/nix/install | sh -s -- --no-daemon --no-channel-add --no-modify-profile' \
  && echo "[nix] bootstrap complete" \
  || echo "[nix] bootstrap FAILED — continuing without nix; rerun by restarting the container"

exit 0
