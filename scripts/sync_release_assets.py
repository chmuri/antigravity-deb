#!/usr/bin/env python3
"""
sync_release_assets.py - Downloads published .deb assets from GitHub Releases for APT indexing.
"""
import json
import os
import subprocess
import sys
import urllib.request

target_dir = sys.argv[1] if len(sys.argv) > 1 else "repo-dist"
repo = os.environ.get("GITHUB_REPOSITORY", "chmuri/antigravity-deb")
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")

os.makedirs(target_dir, exist_ok=True)

url = f"https://api.github.com/repos/{repo}/releases?per_page=100"
headers = {"User-Agent": "antigravity-builder", "Accept": "application/vnd.github+json"}
if token:
    headers["Authorization"] = f"Bearer {token}"

try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=15) as resp:
        releases = json.loads(resp.read().decode("utf-8"))

    for r in releases:
        for a in r.get("assets", []):
            name = a.get("name", "")
            dl_url = a.get("browser_download_url", "")
            dest = os.path.join(target_dir, name)
            if name.endswith(".deb") and not os.path.exists(dest):
                print(f"[INFO] Downloading existing release asset {name} for APT indexing...")
                subprocess.run(["curl", "-fsSL", "-o", dest, dl_url], check=True)
except Exception as e:
    print(f"[NOTICE] Release asset synchronization: {e}", file=sys.stderr)
