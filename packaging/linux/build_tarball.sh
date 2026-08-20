#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

VERSION="${RELEASE_TAG:-}"
VERSION="${VERSION#v}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(awk '/^version:/ { print $2; exit }' app/pubspec.yaml | cut -d+ -f1)"
fi
if [[ -z "$VERSION" ]]; then
  echo "Could not determine version (set RELEASE_TAG or check app/pubspec.yaml)" >&2
  exit 1
fi

BUNDLE="$REPO_ROOT/app/build/linux/x64/release/bundle"
if [[ ! -x "$BUNDLE/remote_pi" ]]; then
  echo "Linux bundle not found at $BUNDLE" >&2
  echo "Build it first: (cd app && flutter build linux --release)" >&2
  exit 1
fi

STAGING="$REPO_ROOT/build/linux-tarball"
OUTDIR="$REPO_ROOT/dist"
NAME="RemotePi-linux-x64-${VERSION}"

rm -rf "$STAGING"
mkdir -p "$STAGING/$NAME" "$OUTDIR"

cp -a "$BUNDLE/." "$STAGING/$NAME/"
cp packaging/linux/remotepi.desktop "$STAGING/$NAME/"
cp packaging/linux/remotepi.png "$STAGING/$NAME/"
cp LICENSE "$STAGING/$NAME/"

tar -C "$STAGING" -czf "$OUTDIR/${NAME}.tar.gz" "$NAME"
echo "Built $OUTDIR/${NAME}.tar.gz"
