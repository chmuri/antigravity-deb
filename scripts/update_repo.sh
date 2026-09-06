#!/usr/bin/env bash
# update_repo.sh - Generates APT repository metadata (Packages, Packages.gz, Release, InRelease)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

REPO_DIR="${1:-/output}"
GITHUB_REPO="${GITHUB_REPO:-chmuri/antigravity-deb}"
GPG_KEY_ID="${GPG_KEY_ID:-18EBB53D09F5866F73EB94CF81435F158DF507A0}"

mkdir -p "$REPO_DIR"

# Copy public.key if present in source tree or repo
if [ -f "$PARENT_DIR/public.key" ]; then
  cp -f "$PARENT_DIR/public.key" "$REPO_DIR/public.key"
elif [ -f "/public.key" ]; then
  cp -f "/public.key" "$REPO_DIR/public.key"
fi

cd "$REPO_DIR"

DEB_COUNT="$(find . -maxdepth 2 -name "*.deb" | wc -l)"
if [ "$DEB_COUNT" -eq 0 ] && [ ! -f "Packages" ]; then
  echo "[INFO] No .deb packages found in $REPO_DIR to index."
  exit 0
fi

echo "[INFO] Indexing packages in $REPO_DIR (found $DEB_COUNT .deb files)..."

# Generate Packages file using dpkg-scanpackages or manual inspection
if command -v dpkg-scanpackages >/dev/null 2>&1; then
  dpkg-scanpackages --multiversion . /dev/null > Packages.raw
else
  > Packages.raw
  for deb in $(find . -maxdepth 2 -name "*.deb" | sort); do
    [ -f "$deb" ] || continue
    dpkg-deb -I "$deb" control > /tmp/ctrl.$$
    sed -i '/^$/d' /tmp/ctrl.$$
    cat /tmp/ctrl.$$ >> Packages.raw
    echo "Filename: $deb" >> Packages.raw
    echo "Size: $(stat -c%s "$deb")" >> Packages.raw
    echo "MD5sum: $(md5sum "$deb" | cut -d' ' -f1)" >> Packages.raw
    echo "SHA256: $(sha256sum "$deb" | cut -d' ' -f1)" >> Packages.raw
    echo "" >> Packages.raw
    rm -f /tmp/ctrl.$$
  done
fi

# If GITHUB_REPO is provided, transform Filename to GitHub Releases direct asset URL
python3 - "Packages.raw" "Packages.new" "$GITHUB_REPO" <<'PY'
import re, sys
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
dst = Path(sys.argv[2])
repo = sys.argv[3] if len(sys.argv) > 3 else ""

blocks = src.split('\n\n')
out_blocks = []

for block in blocks:
    if not block.strip():
        continue
    lines = block.splitlines()
    pkg, ver = "", ""
    filename_idx = -1
    for i, line in enumerate(lines):
        if line.startswith('Package: '):
            pkg = line.split('Package: ', 1)[1].strip()
        elif line.startswith('Version: '):
            ver = line.split('Version: ', 1)[1].strip()
        elif line.startswith('Filename: '):
            filename_idx = i

    if filename_idx != -1:
        current_fn = lines[filename_idx].split('Filename: ', 1)[1].strip()
        deb_basename = current_fn.split('/')[-1]
        if repo and pkg and ver:
            tag = f"{pkg}-v{ver}"
            release_url = f"https://github.com/{repo}/releases/download/{tag}/{deb_basename}"
            lines[filename_idx] = f"Filename: {release_url}"

    out_blocks.append('\n'.join(lines))

dst.write_text('\n\n'.join(out_blocks) + '\n', encoding='utf-8')
PY

mv -f Packages.new Packages
rm -f Packages.raw

# Compress Packages index
gzip -9c Packages > Packages.gz
if command -v xz >/dev/null 2>&1; then
  xz -9c Packages > Packages.xz 2>/dev/null || true
fi

# Generate Debian Release file
DATE_STR="$(date -Ru)"

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

if [ -f "Packages.xz" ]; then
  cat >> Release.new <<EOF
 $(sha256sum Packages.xz | awk '{print $1 " "}')$(stat -c%s Packages.xz) Packages.xz
EOF
fi

mv -f Release.new Release

# GPG Signing
if command -v gpg >/dev/null 2>&1; then
  # Check if private key for GPG_KEY_ID exists in gpg keyring
  if gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1 || gpg --list-secret-keys >/dev/null 2>&1; then
    echo "[INFO] Signing Release with GPG Key: $GPG_KEY_ID..."
    rm -f InRelease Release.gpg
    gpg --clearsign --batch --yes --armor --digest-algo SHA512 -u "$GPG_KEY_ID" -o InRelease Release
    gpg --detach-sign --batch --yes --armor --digest-algo SHA512 -u "$GPG_KEY_ID" -o Release.gpg Release
    echo "[SUCCESS] InRelease and Release.gpg created."
  else
    echo "[WARN] GPG secret key for $GPG_KEY_ID not found in keyring. Skipping signature."
  fi
else
  echo "[WARN] GPG binary not found. Skipping repository signing."
fi

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
      --accent-hover: #0284c7;
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

# 3. Add the APT source
echo "deb [signed-by=/etc/apt/keyrings/antigravity.gpg] https://chmuri.github.io/antigravity-deb/ ./" | sudo tee /etc/apt/sources.list.d/antigravity.list

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

echo "[SUCCESS] APT repository indexes generated: Packages, Packages.gz, Release, index.html"
