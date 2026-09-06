#!/usr/bin/env bash
# build_deb.sh - Builds a clean, official Debian/Ubuntu .deb package for Google Antigravity
# Usage: build_deb.sh <product: desktop|ide> <version> <download_url> <arch: amd64|arm64> <output_dir>
set -euo pipefail

PRODUCT="${1:-}"
VERSION="${2:-}"
URL="${3:-}"
ARCH="${4:-amd64}"
OUTPUT_DIR="${5:-/output}"

if [ -z "$PRODUCT" ] || [ -z "$VERSION" ] || [ -z "$URL" ]; then
  echo "Usage: $0 <desktop|ide> <version> <url> [arch] [output_dir]" >&2
  exit 1
fi

DEB_ARCH="$ARCH"
case "$DEB_ARCH" in
  amd64|x86_64) DEB_ARCH="amd64"; AG_PLATFORM="linux-x64" ;;
  arm64|aarch64) DEB_ARCH="arm64"; AG_PLATFORM="linux-arm" ;;
  *) echo "ERROR: Unsupported architecture $ARCH" >&2; exit 1 ;;
esac

mkdir -p "$OUTPUT_DIR"

if [ "$PRODUCT" = "desktop" ]; then
  PKG_NAME="antigravity"
  PKG_TITLE="Google Antigravity 2.0"
  PKG_SHORT_DESC="Google Antigravity 2.0 - Agentic AI Development Platform"
  PKG_LONG_DESC=" Google Antigravity 2.0 is an advanced desktop agent platform designed for
 autonomous AI engineering, multi-agent orchestration, and developer workflows.
 .
 This package contains the official Antigravity 2.0 desktop application for Linux,
 packaged into standard Debian/Ubuntu format with desktop integration, icons,
 and sandbox security configurations.
 .
 Upstream releases: https://antigravity.google
 Package repository: https://github.com/chmuri/antigravity-deb"
  INSTALL_ROOT="/opt/antigravity"
  BIN_NAME="antigravity"
elif [ "$PRODUCT" = "ide" ]; then
  PKG_NAME="antigravity-ide"
  PKG_TITLE="Google Antigravity IDE"
  PKG_SHORT_DESC="Google Antigravity IDE - Agent-First Development Environment"
  PKG_LONG_DESC=" Google Antigravity IDE is a next-generation integrated development environment
 optimized for AI pair-programming, agent collaboration, and codebase intelligence.
 .
 This package contains the official Antigravity IDE for Linux, complete with
 desktop shortcuts, icons, and GNOME Files (Nautilus) file manager integration.
 .
 Upstream releases: https://antigravity.google
 Package repository: https://github.com/chmuri/antigravity-deb"
  INSTALL_ROOT="/opt/antigravity-ide"
  BIN_NAME="antigravity-ide"
else
  echo "ERROR: Unknown product $PRODUCT (must be 'desktop' or 'ide')" >&2
  exit 1
fi

FINAL_DEB="${OUTPUT_DIR}/${PKG_NAME}_${VERSION}_${DEB_ARCH}.deb"

if [ -f "$FINAL_DEB" ]; then
  echo "[INFO] Package $FINAL_DEB already exists. Skipping build."
  exit 0
fi

echo "========================================================"
echo " Building package: $PKG_NAME v$VERSION ($DEB_ARCH)"
echo " Source URL:       $URL"
echo " Target .deb:      $FINAL_DEB"
echo "========================================================"

BUILD_TMP="$(mktemp -d /tmp/deb-builder.XXXXXX)"
cleanup() {
  rm -rf "$BUILD_TMP"
}
trap cleanup EXIT

# 1. Download source archive
ARCHIVE_PATH="$BUILD_TMP/source.tar.gz"
echo "[1/5] Downloading official archive..."
curl -fsSL --retry 3 --retry-delay 2 -o "$ARCHIVE_PATH" "$URL"

# 2. Extract archive
EXTRACT_DIR="$BUILD_TMP/extracted"
mkdir -p "$EXTRACT_DIR"
echo "[2/5] Extracting archive..."
tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"

# Identify top-level extracted folder
TOP_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$TOP_DIR" ]; then
  echo "ERROR: Failed to find extracted application directory" >&2
  exit 1
fi

# 3. Create staging directory for .deb
STAGING="$BUILD_TMP/staging"
mkdir -p "$STAGING/DEBIAN"
mkdir -p "$STAGING$INSTALL_ROOT"
mkdir -p "$STAGING/usr/bin"
mkdir -p "$STAGING/usr/share/applications"
mkdir -p "$STAGING/usr/share/icons/hicolor/512x512/apps"

# Copy application files to /opt/<pkg>
echo "[3/5] Staging application files into $INSTALL_ROOT..."
cp -a "$TOP_DIR/." "$STAGING$INSTALL_ROOT/"

# Locate main executable
LAUNCHER=""
if [ -f "$STAGING$INSTALL_ROOT/$BIN_NAME" ]; then
  LAUNCHER="$INSTALL_ROOT/$BIN_NAME"
elif [ -f "$STAGING$INSTALL_ROOT/antigravity" ]; then
  LAUNCHER="$INSTALL_ROOT/antigravity"
elif [ -f "$STAGING$INSTALL_ROOT/antigravity-ide" ]; then
  LAUNCHER="$INSTALL_ROOT/antigravity-ide"
else
  # Check subdirectories if nested
  FOUND_BIN="$(find "$STAGING$INSTALL_ROOT" -maxdepth 2 -type f -name "$BIN_NAME" | head -n 1)"
  if [ -n "$FOUND_BIN" ]; then
    LAUNCHER="${FOUND_BIN#"$STAGING"}"
  fi
fi

if [ -z "$LAUNCHER" ]; then
  echo "ERROR: Main launcher binary not found in $INSTALL_ROOT" >&2
  exit 1
fi
chmod +x "$STAGING$LAUNCHER"

# Create symlink in /usr/bin/
ln -s "$LAUNCHER" "$STAGING/usr/bin/$BIN_NAME"

# Extract and install icons
ICON_DEST="$STAGING/usr/share/icons/hicolor/512x512/apps/${PKG_NAME}.png"
if [ "$PRODUCT" = "desktop" ]; then
  # Desktop icon is inside resources/app.asar
  ASAR_FILE="$(find "$STAGING$INSTALL_ROOT" -name "app.asar" | head -n 1)"
  if [ -n "$ASAR_FILE" ] && [ -f "$ASAR_FILE" ]; then
    python3 - "$ASAR_FILE" "$ICON_DEST" <<'PY' || true
import json, struct, sys
from pathlib import Path
asar = Path(sys.argv[1])
out = Path(sys.argv[2])
try:
    with asar.open('rb') as f:
        f.read(4)
        header_size = struct.unpack('<I', f.read(4))[0]
        f.read(4)
        json_size = struct.unpack('<I', f.read(4))[0]
        header = json.loads(f.read(json_size).decode())
    icon = header.get('files', {}).get('icon.png')
    if icon:
        with asar.open('rb') as f:
            f.seek(8 + header_size + int(icon['offset']))
            out.write_bytes(f.read(int(icon['size'])))
except Exception as e:
    sys.exit(1)
PY
  fi
elif [ "$PRODUCT" = "ide" ]; then
  IDE_ICON="$(find "$STAGING$INSTALL_ROOT" -name "code.png" | head -n 1)"
  if [ -n "$IDE_ICON" ] && [ -f "$IDE_ICON" ]; then
    cp -f "$IDE_ICON" "$ICON_DEST"
  fi
fi

# Fallback transparent/default png if icon extraction failed
if [ ! -f "$ICON_DEST" ]; then
  echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > "$ICON_DEST" 2>/dev/null || true
fi
chmod 644 "$ICON_DEST" 2>/dev/null || true

# Create Desktop Entry
DESKTOP_ENTRY="$STAGING/usr/share/applications/${PKG_NAME}.desktop"
if [ "$PRODUCT" = "desktop" ]; then
  cat > "$DESKTOP_ENTRY" <<EOF
[Desktop Entry]
Name=$PKG_TITLE
Comment=$PKG_DESC
Exec=/usr/bin/$BIN_NAME %U
Icon=$PKG_NAME
Terminal=false
Type=Application
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=Antigravity
EOF
elif [ "$PRODUCT" = "ide" ]; then
  cat > "$DESKTOP_ENTRY" <<EOF
[Desktop Entry]
Name=$PKG_TITLE
Comment=$PKG_DESC
Exec=/usr/bin/$BIN_NAME %F
Icon=$PKG_NAME
Terminal=false
Type=Application
Categories=Development;IDE;
MimeType=inode/directory;text/plain;application/x-code-workspace;application/x-antigravity-workspace;x-scheme-handler/antigravity-ide;
StartupNotify=true
StartupWMClass=antigravity-ide
EOF
  # Nautilus context menu extension
  mkdir -p "$STAGING/usr/share/nautilus-python/extensions"
  cat > "$STAGING/usr/share/nautilus-python/extensions/open-in-antigravity-ide.py" <<'PY'
import subprocess
from urllib.parse import unquote, urlparse
from gi.repository import Nautilus, GObject

class OpenInAntigravityIDE(GObject.GObject, Nautilus.MenuProvider):
    def _path(self, file_info):
        uri = file_info.get_uri()
        parsed = urlparse(uri)
        if parsed.scheme != 'file':
            return None
        return unquote(parsed.path)

    def get_file_items(self, files):
        if not files or len(files) != 1:
            return []
        path = self._path(files[0])
        if not path:
            return []
        item = Nautilus.MenuItem(
            name='OpenInAntigravityIDE::open',
            label='Open in Antigravity IDE',
            tip='Open this folder or file in Antigravity IDE'
        )
        item.connect('activate', lambda _item: subprocess.Popen(['antigravity-ide', path]))
        return [item]

    def get_background_items(self, folder):
        path = self._path(folder)
        if not path:
            return []
        item = Nautilus.MenuItem(
            name='OpenInAntigravityIDE::open_background',
            label='Open Folder in Antigravity IDE',
            tip='Open the current folder in Antigravity IDE'
        )
        item.connect('activate', lambda _item: subprocess.Popen(['antigravity-ide', path]))
        return [item]
PY
  chmod 644 "$STAGING/usr/share/nautilus-python/extensions/open-in-antigravity-ide.py"
fi
chmod 644 "$DESKTOP_ENTRY"

# Calculate installed size in KB
INSTALLED_SIZE="$(du -sk "$STAGING" | cut -f1)"

# 4. Generate Debian control scripts
echo "[4/5] Generating Debian package metadata..."
cat > "$STAGING/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Section: devel
Priority: optional
Architecture: $DEB_ARCH
Installed-Size: $INSTALLED_SIZE
Maintainer: Antigravity Community <antigravity-deb@users.noreply.github.com>
Homepage: https://antigravity.google
Depends: ca-certificates, xdg-utils, desktop-file-utils, libnss3, libasound2t64 | libasound2, libgtk-3-0
Recommends: python3-nautilus
Description: $PKG_SHORT_DESC
$PKG_LONG_DESC
EOF

cat > "$STAGING/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

# Fix chrome-sandbox permissions if present
find /opt/antigravity* -type f -name "chrome-sandbox" -exec chown root:root {} + -exec chmod 4755 {} + 2>/dev/null || true

# Update desktop and icon databases
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi

exit 0
EOF
chmod 755 "$STAGING/DEBIAN/postinst"

cat > "$STAGING/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi

exit 0
EOF
chmod 755 "$STAGING/DEBIAN/postrm"

# 5. Build .deb package
echo "[5/5] Building .deb package with dpkg-deb..."
dpkg-deb --build --root-owner-group "$STAGING" "$FINAL_DEB"

echo "[SUCCESS] Successfully built: $FINAL_DEB"
dpkg-deb -I "$FINAL_DEB"
