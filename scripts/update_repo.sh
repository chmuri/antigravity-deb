#!/usr/bin/env bash
# update_repo.sh - Generates standard Debian APT repository metadata (dists/stable/...)
# Supports both:
#   deb https://.../antigravity-deb stable main
#   deb https://.../antigravity-deb/ ./  (flat fallback)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

REPO_DIR="${1:-/output}"
GITHUB_REPO="${GITHUB_REPO:-chmuri/antigravity-deb}"
GPG_KEY_ID="${GPG_KEY_ID:-18EBB53D09F5866F73EB94CF81435F158DF507A0}"

mkdir -p "$REPO_DIR"

# Copy public.key if present
if [ -f "$PARENT_DIR/public.key" ]; then
  cp -f "$PARENT_DIR/public.key" "$REPO_DIR/public.key"
elif [ -f "/public.key" ]; then
  cp -f "/public.key" "$REPO_DIR/public.key"
fi

cd "$REPO_DIR"

DEB_COUNT="$(find . -maxdepth 3 -name "*.deb" | wc -l)"
if [ "$DEB_COUNT" -eq 0 ] && [ ! -f "Packages" ] && [ ! -d "dists" ]; then
  echo "[INFO] No .deb packages found in $REPO_DIR to index."
  exit 0
fi

echo "[INFO] Indexing packages in $REPO_DIR (found $DEB_COUNT .deb files)..."

# Target structure for standard Debian repository
DIST_NAME="stable"
DIST_DIR="dists/$DIST_NAME"
MAIN_AMD64="$DIST_DIR/main/binary-amd64"
MAIN_ARM64="$DIST_DIR/main/binary-arm64"
mkdir -p "$MAIN_AMD64" "$MAIN_ARM64"

# Generate raw Packages for all debs
if command -v dpkg-scanpackages >/dev/null 2>&1; then
  dpkg-scanpackages --multiversion . /dev/null > Packages.all.raw
else
  > Packages.all.raw
  for deb in $(find . -maxdepth 3 -name "*.deb" | sort); do
    [ -f "$deb" ] || continue
    dpkg-deb -I "$deb" control > /tmp/ctrl.$$
    sed -i '/^$/d' /tmp/ctrl.$$
    cat /tmp/ctrl.$$ >> Packages.all.raw
    echo "Filename: $deb" >> Packages.all.raw
    echo "Size: $(stat -c%s "$deb")" >> Packages.all.raw
    echo "MD5sum: $(md5sum "$deb" | cut -d' ' -f1)" >> Packages.all.raw
    echo "SHA256: $(sha256sum "$deb" | cut -d' ' -f1)" >> Packages.all.raw
    echo "" >> Packages.all.raw
    rm -f /tmp/ctrl.$$
  done
fi

# Transform Filename to GitHub Releases direct asset URLs and split by architecture
python3 - "Packages.all.raw" "$MAIN_AMD64/Packages" "$MAIN_ARM64/Packages" "Packages" "$GITHUB_REPO" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
dst_amd64 = Path(sys.argv[2])
dst_arm64 = Path(sys.argv[3])
dst_flat = Path(sys.argv[4])
repo = sys.argv[5] if len(sys.argv) > 5 else ""

blocks = src.split('\n\n')
amd64_blocks = []
arm64_blocks = []
all_blocks = []

for block in blocks:
    if not block.strip():
        continue
    lines = block.splitlines()
    pkg, ver, arch = "", "", ""
    filename_idx = -1
    for i, line in enumerate(lines):
        if line.startswith('Package: '):
            pkg = line.split('Package: ', 1)[1].strip()
        elif line.startswith('Version: '):
            ver = line.split('Version: ', 1)[1].strip()
        elif line.startswith('Architecture: '):
            arch = line.split('Architecture: ', 1)[1].strip()
        elif line.startswith('Filename: '):
            filename_idx = i

    if filename_idx != -1:
        current_fn = lines[filename_idx].split('Filename: ', 1)[1].strip()
        deb_basename = current_fn.split('/')[-1]
        if repo and pkg and ver:
            tag = f"{pkg}-v{ver}"
            release_url = f"https://github.com/{repo}/releases/download/{tag}/{deb_basename}"
            lines[filename_idx] = f"Filename: {release_url}"

    formatted_block = '\n'.join(lines)
    all_blocks.append(formatted_block)
    if arch in ('amd64', 'all'):
        amd64_blocks.append(formatted_block)
    if arch in ('arm64', 'all'):
        arm64_blocks.append(formatted_block)

dst_flat.write_text('\n\n'.join(all_blocks) + ('\n' if all_blocks else ''), encoding='utf-8')
dst_amd64.write_text('\n\n'.join(amd64_blocks) + ('\n' if amd64_blocks else ''), encoding='utf-8')
dst_arm64.write_text('\n\n'.join(arm64_blocks) + ('\n' if arm64_blocks else ''), encoding='utf-8')
PY

rm -f Packages.all.raw

# Compress Packages for all architectures
for p_file in "$MAIN_AMD64/Packages" "$MAIN_ARM64/Packages" "Packages"; do
  gzip -9c "$p_file" > "${p_file}.gz"
  if command -v xz >/dev/null 2>&1; then
    xz -9c "$p_file" > "${p_file}.xz" 2>/dev/null || true
  fi
done

# Generate Release for dists/stable/
DATE_STR="$(date -Ru)"

cat > "$DIST_DIR/Release.new" <<EOF
Origin: Google Antigravity Repository
Label: Antigravity Packages
Suite: $DIST_NAME
Codename: $DIST_NAME
Components: main
Architectures: amd64 arm64
Date: $DATE_STR
Description: Debian/Ubuntu APT repository for Google Antigravity 2.0 and Antigravity IDE
MD5Sum:
EOF

for sub in "main/binary-amd64/Packages" "main/binary-amd64/Packages.gz" "main/binary-amd64/Packages.xz" \
           "main/binary-arm64/Packages" "main/binary-arm64/Packages.gz" "main/binary-arm64/Packages.xz"; do
  if [ -f "$DIST_DIR/$sub" ]; then
    echo " $(md5sum "$DIST_DIR/$sub" | awk '{print $1 " "}')$(stat -c%s "$DIST_DIR/$sub") $sub" >> "$DIST_DIR/Release.new"
  fi
done

echo "SHA256:" >> "$DIST_DIR/Release.new"
for sub in "main/binary-amd64/Packages" "main/binary-amd64/Packages.gz" "main/binary-amd64/Packages.xz" \
           "main/binary-arm64/Packages" "main/binary-arm64/Packages.gz" "main/binary-arm64/Packages.xz"; do
  if [ -f "$DIST_DIR/$sub" ]; then
    echo " $(sha256sum "$DIST_DIR/$sub" | awk '{print $1 " "}')$(stat -c%s "$DIST_DIR/$sub") $sub" >> "$DIST_DIR/Release.new"
  fi
done

mv -f "$DIST_DIR/Release.new" "$DIST_DIR/Release"

# Also generate flat Release at root for backwards compatibility
cat > Release.new <<EOF
Origin: Google Antigravity Repository
Label: Antigravity Packages
Suite: stable
Codename: stable
Components: main
Architectures: amd64 arm64
Date: $DATE_STR
Description: Unofficial Debian/Ubuntu APT repository for Google Antigravity 2.0 and Antigravity IDE
MD5Sum:
 $(md5sum Packages | awk '{print $1 " "}')$(stat -c%s Packages) Packages
 $(md5sum Packages.gz | awk '{print $1 " "}')$(stat -c%s Packages.gz) Packages.gz
SHA256:
 $(sha256sum Packages | awk '{print $1 " "}')$(stat -c%s Packages) Packages
 $(sha256sum Packages.gz | awk '{print $1 " "}')$(stat -c%s Packages.gz) Packages.gz
EOF
mv -f Release.new Release

# GPG Signing function
sign_release() {
  local target_dir="$1"
  if command -v gpg >/dev/null 2>&1; then
    if gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1 || gpg --list-secret-keys >/dev/null 2>&1; then
      echo "[INFO] Signing $target_dir/Release with GPG Key: $GPG_KEY_ID..."
      rm -f "$target_dir/InRelease" "$target_dir/Release.gpg"
      gpg --clearsign --batch --yes --armor --digest-algo SHA512 -u "$GPG_KEY_ID" -o "$target_dir/InRelease" "$target_dir/Release"
      gpg --detach-sign --batch --yes --armor --digest-algo SHA512 -u "$GPG_KEY_ID" -o "$target_dir/Release.gpg" "$target_dir/Release"
      echo "[SUCCESS] $target_dir/InRelease and Release.gpg created."
    fi
  fi
}

sign_release "$DIST_DIR"
sign_release "."

# Generate modern index.html for GitHub Pages
cat > index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Google Antigravity - Debian/Ubuntu APT Repository</title>
  <style>
    :root {
      --bg: #0f172a;
      --card: #1e293b;
      --border: #334155;
      --text: #f8fafc;
      --muted: #94a3b8;
      --accent: #38bdf8;
      --code-bg: #090d16;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background-color: var(--bg);
      color: var(--text);
      line-height: 1.6;
      margin: 0;
      padding: 2rem 1rem;
    }
    .container {
      max-width: 860px;
      margin: 0 auto;
    }
    header {
      text-align: center;
      margin-bottom: 2.5rem;
    }
    h1 {
      font-size: 2.2rem;
      font-weight: 800;
      color: var(--accent);
      margin-bottom: 0.5rem;
    }
    p.lead {
      font-size: 1.15rem;
      color: var(--muted);
    }
    .card {
      background-color: var(--card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1.5rem;
      margin-bottom: 1.5rem;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.2);
    }
    h2 {
      margin-top: 0;
      font-size: 1.35rem;
      color: var(--text);
      border-bottom: 1px solid var(--border);
      padding-bottom: 0.5rem;
    }
    pre {
      background-color: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1rem;
      overflow-x: auto;
      font-size: 0.95rem;
      color: #e2e8f0;
    }
    code {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    }
    a {
      color: var(--accent);
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    footer {
      text-align: center;
      margin-top: 3rem;
      color: var(--muted);
      font-size: 0.9rem;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>Google Antigravity APT Repository</h1>
      <p class="lead">Official-grade automated Debian/Ubuntu packages for Google Antigravity 2.0 and Antigravity IDE</p>
    </header>

    <div class="card">
      <h2>🚀 Quick Setup (Ubuntu / Debian)</h2>
      <p>Run the following commands to add the GPG key and APT repository to your system:</p>
      <pre><code># 1. Install prerequisites
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg

# 2. Add the repository GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://chmuri.github.io/antigravity-deb/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/antigravity.gpg
sudo chmod a+r /etc/apt/keyrings/antigravity.gpg

# 3. Add the APT source (stable)
echo "deb [signed-by=/etc/apt/keyrings/antigravity.gpg] https://chmuri.github.io/antigravity-deb stable main" | sudo tee /etc/apt/sources.list.d/antigravity.list

# 4. Update and install Antigravity
sudo apt-get update
sudo apt-get install -y antigravity antigravity-ide</code></pre>
    </div>

    <div class="card">
      <h2>📦 Available Packages</h2>
      <ul>
        <li><strong>antigravity</strong>: Google Antigravity 2.0 desktop agent platform</li>
        <li><strong>antigravity-ide</strong>: Google Antigravity IDE development environment</li>
      </ul>
      <p>Direct download links and release changelogs are available on <a href="https://github.com/chmuri/antigravity-deb/releases" target="_blank">GitHub Releases</a>.</p>
    </div>

    <footer>
      <p>Automated APT Repository &bull; Source on <a href="https://github.com/chmuri/antigravity-deb">GitHub</a></p>
    </footer>
  </div>
</body>
</html>
HTML

echo "[SUCCESS] Standard Debian repository (dists/$DIST_NAME/...) and flat index generated successfully."
