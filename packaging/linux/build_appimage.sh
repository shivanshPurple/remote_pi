#!/usr/bin/env bash
set -euo pipefail

# Ensure we're in repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

APPDIR="$REPO_ROOT/build/AppDir"
OUTDIR="$REPO_ROOT/dist"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/icons/hicolor/256x256/apps" "$OUTDIR"

# Copy Linux build bundle
cp -r app/build/linux/x64/release/bundle/* "$APPDIR/usr/bin/"

# Copy icon and desktop entry
cp packaging/linux/remotepi.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/remotepi.png"
cp packaging/linux/remotepi.png "$APPDIR/remotepi.png"
cp packaging/linux/remotepi.desktop "$APPDIR/remotepi.desktop"

# Create AppRun script
cat << 'EOF' > "$APPDIR/AppRun"
#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin/:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/bin/lib:${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/app" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Download appimagetool if not present
if [ ! -f /tmp/appimagetool ]; then
  curl -fsSL -o /tmp/appimagetool https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-x86_64.AppImage
  chmod +x /tmp/appimagetool
fi

# Build AppImage
ARCH=x86_64 /tmp/appimagetool --appimage-extract-and-run "$APPDIR" "$OUTDIR/RemotePi-x86_64.AppImage"
echo "Built AppImage: $OUTDIR/RemotePi-x86_64.AppImage"
