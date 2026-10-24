# flat2appimage

Build AppImages from a Flathub manifest. One command, two variants, zsync files included.
Everything runs inside a container (toolbox by default, podman optional).

Status: working, early. Verified with `io.github.tobagin.karere` (Rust + CEF, yml manifest) and
`com.github.tchx84.Flatseal` (gjs + meson, JSON manifest). Design details live in
`docs/flat2appimage-plan.md`.

## Requirements

- Linux host with `toolbox` (recommended) or `podman`, plus network access on the first run.
- Disk: a few GB. The GNOME runtime/SDK are ~1.5 GB, big app payloads (CEF) add more.
- The first run creates the `flat2appimage` container and installs flatpak-builder and friends inside it.

## Quick start

Build straight from Flathub, no local checkout needed:

```sh
./flat2appimage https://github.com/flathub/io.github.tobagin.karere/blob/master/io.github.tobagin.karere.yml
```

A local manifest file works too:

```sh
./flat2appimage path/to/io.github.tobagin.karere.yml
```

GitHub `blob` URLs are converted to raw automatically. For GitHub URLs the whole manifest
directory is fetched (many apps need sibling files like `cargo-sources.json` or patches) and
cached in `~/.cache/flat2appimage/manifests/<app>/`.

Artifacts land in `dist/`:

```sh
Karere-4.3.4-x86_64.AppImage           + .zsync   small, needs a GNOME-ish host
Karere-4.3.4-anylinux-x86_64.AppImage  + .zsync   larger, runs anywhere
```

Update an old local copy over zsync:

```sh
zsync http://server/path/Karere-4.3.4-x86_64.AppImage.zsync
```

## Options

Run `./flat2appimage --help` for the full list.

| Option | Purpose |
| --- | --- |
| `--variant all\|squashfs\|anylinux` | build both (default) or one variant |
| `--arch ARCH` | target architecture (default: container `uname -m`) |
| `--dist DIR` | output directory (default `./dist`) |
| `--update-info VALUE` | override the embedded AppImage update info |
| `--app-id ID` | override the app id (default: manifest file name) |
| `--container NAME` | container name (default `flat2appimage`) |
| `--engine toolbox\|podman\|auto` | container engine (default `auto`) |
| `--container-image IMAGE` | image for `--engine podman` |
| `--refresh` | re-download `quick-sharun.sh` |
| `--keep`, `--debug` | keep AppDirs (and enable quick-sharun debug) |
| `--cache` | show cache disk usage, offer to clear it |
| `--clean-cache` | delete the cache (runtimes, builds, downloads) |

## Per-app overrides

Optional `flat2appimage.conf` next to the manifest (sourced by the tool). For URL builds, put it in
`~/.cache/flat2appimage/manifests/<app>/`:

```sh
APP_NAME="MyApp"                           # override the name from the desktop file
EXTRA_BINARIES="/app/lib/mystuff"          # extra dirs/binaries for quick-sharun to bundle
QS_ENV="DEPLOY_ELECTRON=1 STRACE_MODE=0"   # env for quick-sharun (DEPLOY_* flags, STRACE_MODE)
UPDATE_REPO="owner/repo"                   # GitHub repo, for gh-releases-zsync update info
QUICK_SHARUN_URL=... QUICK_SHARUN_SHA=...  # pin or replace quick-sharun
```

## Variants

- squashfs (small): classic AppImage. Uses host libraries, so it targets modern GNOME desktops
  (GTK4, libadwaita, libnss, libgbm, audio). Runtime libraries missing on the build host (e.g. a
  newer libxml2) are bundled; this reads the host library cache, so it needs the toolbox engine.
- anylinux (large): portable. Bundles what the app ships and runs on almost any Linux via sharun.
  WebKitGTK apps may still hit their own process-IPC errors there; prefer the squashfs variant on a
  matching GNOME host.

Quirks handled automatically: yml and JSON manifests; `/app` prefix rewrite in gjs launchers;
absolute `/app` RPATHs in ELF files rewritten to `$ORIGIN`-relative paths;
compiled-in `/app/share`, `/app/lib` and `/app/libexec` paths in binaries (patched to `/tmp`
links made at launch, so Folks/EDS/WebKit find their data);
Flatpak `/run/build/<module>` fallback paths for apps that run from a build tree;
quick-sharun dbus and locale pitfalls; `GSETTINGS_SCHEMA_DIR` for script launchers.

## Caches

- `~/.cache/flat2appimage/`: quick-sharun, static patchelf, and an isolated flatpak user dir with the
  downloaded runtimes/SDKs.
- The container is reused across builds. `toolbox enter flat2appimage` to look inside.
- Run `./flat2appimage --cache` for a size breakdown and an interactive offer to clear it, or
  `./flat2appimage --clean-cache` to delete it directly. Runtimes and tools re-download on the next build.

## Limitations

- squashfs variant assumes a GNOME-ish host, by design.
- JS apps need `gjs` on the host, in both variants (quick-sharun bundles libraries for ELF binaries only).
- Hardcoded `/app` paths in non-gjs launchers (python/shell wrappers) are not rewritten yet.
- aarch64 is not built locally yet; it is planned for GitHub Actions.
- Update info for GitHub releases is not wired up yet; local builds use relative zsync URLs.
