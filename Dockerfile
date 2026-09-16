# opencode + a real development toolchain.
#
# WHY THIS EXISTS
# ghcr.io/brockar/opencoded ships git, gh, ripgrep and jq — enough for an agent
# to clone and read a repo, but not to BUILD or RUN one. It has no python, no
# node, no compiler, not even xz. Agents hit that wall constantly.
#
# The obvious workaround does not work: the image has passwordless sudo, so an
# agent CAN `apt-get install` at runtime — into the container's writable layer,
# which is destroyed on every recreate. Dockhand redeploys are routine, so that
# silently evaporates mid-project. Anything meant to persist has to be either
# baked in here or written to a mounted dataset.
#
# WHAT GOES WHERE — three layers, on purpose:
#
#   1. THIS IMAGE: the part that genuinely needs root. Compilers, headers and
#      base interpreters. Changes rarely; changing it means a CI rebuild and a
#      deliberate tag bump in the compose file.
#
#   2. mise, data on the persisted /opt/tools dataset: per-project language and
#      tool VERSIONS. `mise use node@22` in a project writes .mise.toml into
#      that repo, so the version travels with the code and the runtime itself
#      survives container recreates.
#
#   3. Nix, store on the persisted /nix dataset: everything else. Agents run
#      `nix profile install nixpkgs#<pkg>` to get arbitrary system packages
#      without root and without waiting on a rebuild. Nix is NOT installed here
#      — /nix is a bind mount at runtime and would shadow anything baked in, so
#      it bootstraps once into the dataset (see bootstrap-nix.sh).
ARG BASE_DIGEST=sha256:92c0e532d5c8cd1a927d70ce5299bdbd68b0de4368de69c20a514d6fabecdd9a
FROM ghcr.io/brockar/opencoded@${BASE_DIGEST}

# An ARG declared before FROM is only in scope for the FROM line. Re-declare it
# here or the LABEL interpolations below come out empty.
ARG BASE_DIGEST
ARG VERSION=dev
ARG MISE_VERSION=v2026.9.10

LABEL org.opencontainers.image.source="https://github.com/adriankent/opencoded-dev" \
      org.opencontainers.image.description="opencode with a full dev toolchain: build-essential, python3, mise for per-project runtimes, and Nix for arbitrary packages." \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}"

USER root

# Base interpreters plus the headers native builds reach for. The -dev packages
# are not padding: pip wheels that fall back to source, and any mise runtime not
# served by a precompiled build, fail without them.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config ca-certificates curl wget unzip xz-utils \
      python3 python3-venv python3-pip python3-dev \
      sqlite3 libsqlite3-dev libssl-dev libffi-dev zlib1g-dev \
      libbz2-dev liblzma-dev libreadline-dev tk-dev uuid-dev \
      procps file less \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://mise.run | MISE_VERSION="${MISE_VERSION}" MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && /usr/local/bin/mise --version

COPY bootstrap-nix.sh /usr/local/bin/bootstrap-nix.sh
RUN chmod +x /usr/local/bin/bootstrap-nix.sh

# Mount points for the two persisted datasets. Created here so the paths exist
# even if a deploy forgets the volumes — tools are then ephemeral, but nothing
# crashes at startup.
RUN mkdir -p /opt/tools /nix

# mise state lives on the persisted dataset, NOT in the home directory. Only
# ~/.config/opencode and ~/.local/share/opencode are mounted, so mise's default
# ~/.local/share/mise would be wiped on every recreate.
ENV MISE_DATA_DIR=/opt/tools/mise \
    MISE_CACHE_DIR=/opt/tools/mise/cache \
    MISE_STATE_DIR=/opt/tools/mise/state \
    MISE_YES=1

# SHIMS, not `mise activate`. Agent commands run as non-interactive `bash -c`,
# which never sources .bashrc — a shell-hook activation would silently do
# nothing and agents would get the system python instead of the project's.
# Shims work in any shell, interactive or not. They come first so a project's
# pinned version beats the system one.
ENV PATH=/opt/tools/mise/shims:/nix/var/nix/profiles/per-user/opencoded/profile/bin:/nix/var/nix/profiles/default/bin:$PATH

# nix-command/flakes are needed for `nix profile install nixpkgs#pkg`.
# sandbox=false because the container lacks the privileges Nix's build sandbox
# wants.
#
# Written to /etc/nix/nix.conf rather than ~/.config/nix/nix.conf, because the
# home directory is not persisted and only parts of it are mounted. /etc/nix is
# in the image and nothing mounts over it.
RUN mkdir -p /etc/nix \
    && printf 'experimental-features = nix-command flakes\nsandbox = false\n' > /etc/nix/nix.conf

USER opencoded
