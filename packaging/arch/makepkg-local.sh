#!/usr/bin/env bash
set -euo pipefail

ARCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ARCH_DIR/../.." && pwd)"

pkgver="$(awk -F= '/^pkgver=/ { print $2; exit }' "$ARCH_DIR/PKGBUILD")"
tarball="$REPO_ROOT/dist/RemotePi-linux-x64-${pkgver}.tar.gz"

if [[ ! -f "$tarball" ]]; then
  echo "Tarball not found: $tarball"
  echo "Building it (requires a Flutter linux release bundle)..."
  bash "$REPO_ROOT/packaging/linux/build_tarball.sh"
fi

if [[ ! -f "$tarball" ]]; then
  echo "Still no tarball. Run: (cd app && flutter build linux --release) && bash packaging/linux/build_tarball.sh" >&2
  exit 1
fi

cp -f "$tarball" "$ARCH_DIR/"
cd "$ARCH_DIR"
exec makepkg -si "$@"
