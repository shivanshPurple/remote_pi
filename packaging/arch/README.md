# Arch Linux (local)

The GitHub repo is private, so this is **not** an AUR package. It installs
from the Linux x64 tarball onto your machine via `makepkg`.

```bash
# from the repo root, after a linux release build
(cd app && flutter build linux --release)
bash packaging/linux/build_tarball.sh
bash packaging/arch/makepkg-local.sh
```

That copies `dist/RemotePi-linux-x64-<ver>.tar.gz` next to `PKGBUILD` and runs
`makepkg -si`. The app lands in `/opt/remote-pi` with `/usr/bin/remote-pi`.

Bump `pkgver` in `PKGBUILD` when `app/pubspec.yaml` version changes.

When the repo is public, this PKGBUILD can move to the AUR as `remote-pi-bin`
with `source=` pointed at the GitHub Release tarball.
