# opencoded-dev

`ghcr.io/adriankent/opencoded-dev` — [opencode](https://opencode.ai) with a
development toolchain that actually survives a container recreate.

Built on [`ghcr.io/brockar/opencoded`](https://github.com/brockar/opencoded),
which provides opencode plus git, gh, ripgrep and jq. That is enough for an
agent to clone and read a repository, but not to build or run one: it has no
python, no node, no compiler, not even `xz`.

## Why not just install things at runtime?

The base image has passwordless sudo, so an agent *can* `apt-get install`. Those
files land in the container's writable layer and are destroyed on the next
recreate — which, under a GitOps deploy tool, is routine. The install appears to
work and then silently vanishes, usually mid-project.

Anything meant to last has to be baked into the image or written to a mounted
volume. This image does both, in three layers:

| Layer | Holds | Changes by |
|---|---|---|
| **Image** | compilers, headers, base interpreters | CI rebuild + tag bump |
| **mise** → `/opt/tools` | per-project language/tool *versions* | agent, instantly |
| **Nix** → `/nix` | arbitrary packages | agent, instantly |

## Per-project runtimes

```sh
mise use node@22        # writes .mise.toml into the project
mise use python@3.12
```

The version travels with the repository, and the runtime itself lives on the
`/opt/tools` volume, so it survives recreates.

mise is wired up with **shims on `PATH`**, not `mise activate`. Agent commands
run as non-interactive `bash -c`, which never sources `.bashrc` — a shell-hook
activation silently does nothing there, and you get the system interpreter
instead of the project's. Shims work in any shell.

## Arbitrary packages

```sh
nix profile install nixpkgs#ffmpeg
```

No root, no rebuild, persists across recreates.

Nix is **not** installed in the image on purpose: `/nix` is a bind mount at
runtime and would shadow anything baked in. `bootstrap-nix.sh` installs it into
the volume on first start instead. That script never fails the container — a
network blip costs you `nix` until the next restart, not the whole environment.

## Required volumes

Both must be writable by uid 1000, and both must persist:

```yaml
volumes:
  - /mnt/opencode-tools:/opt/tools   # mise runtimes
  - /mnt/opencode-nix:/nix           # nix store
```

Without them the image still runs, but every tool an agent installs is
ephemeral — the exact problem it exists to solve.

## Tags

Exact versions only, formatted `YYYY.MM.DD-base<short-digest>` so a tag is
traceable to the upstream image it was built on. **There is no `latest` tag.**
Rolling out is a deliberate act: bump the pinned tag in the consuming compose
file and deploy.
