#!/usr/bin/env python3
"""
discover_versions.py - Discovers both live and historical versions of Google Antigravity.
Supports Antigravity 2.0 Desktop and Antigravity IDE for Linux (amd64, arm64).
"""

import argparse
import gzip
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from typing import Dict, List, Optional, Tuple

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
LIVE_DOWNLOAD_PAGE = "https://antigravity.google/download"

# Known fallback releases to guarantee immediate operation even offline or if CDX is slow
KNOWN_RELEASES = {
    "desktop": {
        "amd64": [
            {
                "version": "2.0.0",
                "build_id": "2.0.0-6324554176528384",
                "url": "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.0.0-6324554176528384/linux-x64/Antigravity.tar.gz"
            },
            {
                "version": "2.12.2",
                "build_id": "2.12.2-6298742303883264",
                "url": "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.12.2-6298742303883264/linux-x64/Antigravity.tar.gz"
            }
        ],
        "arm64": [
            {
                "version": "2.0.0",
                "build_id": "2.0.0-6324554176528384",
                "url": "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.0.0-6324554176528384/linux-arm/Antigravity.tar.gz"
            },
            {
                "version": "2.12.2",
                "build_id": "2.12.2-6298742303883264",
                "url": "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.12.2-6298742303883264/linux-arm/Antigravity.tar.gz"
            }
        ]
    },
    "ide": {
        "amd64": [
            {
                "version": "2.0.1",
                "build_id": "2.0.1-4861014005645312",
                "url": "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.0.1-4861014005645312/linux-x64/Antigravity%20IDE.tar.gz"
            },
            {
                "version": "2.5.5",
                "build_id": "2.5.5-4923483625488384",
                "url": "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz"
            }
        ],
        "arm64": [
            {
                "version": "2.0.1",
                "build_id": "2.0.1-4861014005645312",
                "url": "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.0.1-4861014005645312/linux-arm/Antigravity%20IDE.tar.gz"
            },
            {
                "version": "2.5.5",
                "build_id": "2.5.5-4923483625488384",
                "url": "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-arm/Antigravity%20IDE.tar.gz"
            }
        ]
    }
}


def fetch_url(url: str, timeout: int = 15) -> str:
    """Fetch URL and handle gzip decompression if present."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "gzip, deflate"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            try:
                return gzip.decompress(raw).decode("utf-8", errors="replace")
            except Exception:
                return raw.decode("utf-8", errors="replace")
    except Exception as e:
        print(f"[WARN] Failed to fetch {url}: {e}", file=sys.stderr)
        return ""


def clean_version(raw_version: str) -> str:
    """Extract clean semantic version (e.g. 2.12.2 from 2.12.2-6298742303883264)."""
    m = re.search(r"(\d+\.\d+\.\d+)", raw_version)
    if m:
        return m.group(1)
    return raw_version.split("-")[0].strip()


def parse_version_and_build(url: str) -> Tuple[str, str]:
    """Parse version and full build identifier from URL."""
    decoded = urllib.parse.unquote(url)
    m = re.search(r"/(?:antigravity-hub|stable)/([^/]+)/", decoded)
    if m:
        build_id = m.group(1)
        return clean_version(build_id), build_id
    m2 = re.search(r"/(\d+\.\d+\.\d+(?:-[^/]+)?)/", decoded)
    if m2:
        build_id = m2.group(1)
        return clean_version(build_id), build_id
    return "unknown", "unknown"


def discover_live_versions(arch: str) -> Dict[str, Dict[str, str]]:
    """Scrape live download page and bundle JS for latest versions."""
    platform = "linux-x64" if arch in ("amd64", "x86_64") else "linux-arm"
    results = {}

    html_text = fetch_url(LIVE_DOWNLOAD_PAGE)
    if not html_text:
        return results

    js_urls = [
        urllib.parse.urljoin(LIVE_DOWNLOAD_PAGE, m)
        for m in re.findall(r'(?:src|href)=["\']([^"\']+\.js)["\']', html_text)
    ]

    texts = [html_text]
    for u in js_urls:
        t = fetch_url(u)
        if t:
            texts.append(t)

    desktop_pat = re.compile(rf'https?://[^"\'\s<>)]*/{re.escape(platform)}/Antigravity\.tar\.gz')
    for text in texts:
        matches = desktop_pat.findall(text)
        if matches:
            url = matches[-1]
            ver, build_id = parse_version_and_build(url)
            results["desktop"] = {"version": ver, "build_id": build_id, "url": url}
            break

    ide_pat = re.compile(rf'https?://[^"\'\s<>)]*/{re.escape(platform)}/Antigravity(?:%20|\+| )IDE\.tar\.gz')
    for text in texts:
        matches = ide_pat.findall(text)
        if matches:
            url = matches[-1]
            ver, build_id = parse_version_and_build(url)
            results["ide"] = {"version": ver, "build_id": build_id, "url": url}
            break

    return results


def discover_historical_versions(arch: str) -> Dict[str, List[Dict[str, str]]]:
    """Discover past releases using server-side filtered Wayback Machine CDX API + seeded fallback."""
    platform = "linux-x64" if arch in ("amd64", "x86_64") else "linux-arm"
    norm_arch = "amd64" if arch in ("amd64", "x86_64") else "arm64"

    results: Dict[str, Dict[str, Dict[str, str]]] = {"desktop": {}, "ide": {}}

    # Pre-seed with known releases
    for prod in ("desktop", "ide"):
        for item in KNOWN_RELEASES.get(prod, {}).get(norm_arch, []):
            results[prod][item["version"]] = item

    # Query Wayback Machine CDX API with server-side regex filter for Desktop
    cdx_desktop_url = f"https://web.archive.org/cdx/search/cdx?url=storage.googleapis.com/antigravity-public/antigravity-hub/*&output=json&filter=original:.*{platform}.*tar\\.gz"
    data = fetch_url(cdx_desktop_url, timeout=12)
    if data:
        try:
            entries = json.loads(data)
            for row in entries[1:]:
                orig_url = row[2]
                if f"/{platform}/" in orig_url and orig_url.lower().endswith("antigravity.tar.gz"):
                    ver, build_id = parse_version_and_build(orig_url)
                    if ver != "unknown" and ver.startswith("2."):
                        results["desktop"][ver] = {
                            "version": ver,
                            "build_id": build_id,
                            "url": orig_url
                        }
        except Exception as e:
            print(f"[WARN] Failed parsing CDX desktop data: {e}", file=sys.stderr)

    # Query Wayback Machine CDX API with server-side regex filter for IDE
    cdx_ide_url = f"https://web.archive.org/cdx/search/cdx?url=edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/*&output=json&filter=original:.*{platform}.*tar\\.gz"
    data_ide = fetch_url(cdx_ide_url, timeout=12)
    if data_ide:
        try:
            entries = json.loads(data_ide)
            for row in entries[1:]:
                orig_url = row[2]
                if f"/{platform}/" in orig_url and ("ide" in orig_url.lower() or "%20ide" in orig_url.lower()):
                    ver, build_id = parse_version_and_build(orig_url)
                    if ver != "unknown" and ver.startswith("2."):
                        results["ide"][ver] = {
                            "version": ver,
                            "build_id": build_id,
                            "url": orig_url
                        }
        except Exception as e:
            print(f"[WARN] Failed parsing CDX IDE data: {e}", file=sys.stderr)

    def sort_key(x):
        parts = []
        for p in x["version"].split("."):
            parts.append(int(p) if p.isdigit() else p)
        return parts

    sorted_desktop = sorted(results["desktop"].values(), key=sort_key)
    sorted_ide = sorted(results["ide"].values(), key=sort_key)

    return {"desktop": sorted_desktop, "ide": sorted_ide}


def check_existing_debs(output_dir: str, arch: str) -> Dict[str, set]:
    """Find versions that already have a .deb file in output directory."""
    existing = {"desktop": set(), "ide": set()}
    if not os.path.isdir(output_dir):
        return existing

    deb_arch = "amd64" if arch in ("amd64", "x86_64") else "arm64"
    for root, _, files in os.walk(output_dir):
        for fname in files:
            if not fname.endswith(".deb"):
                continue
            m = re.match(rf"^(antigravity|antigravity-ide)_([0-9\.]+)(?:-[0-9]+)?_{re.escape(deb_arch)}\.deb$", fname)
            if m:
                pkg, ver = m.group(1), m.group(2)
                prod = "ide" if pkg == "antigravity-ide" else "desktop"
                existing[prod].add(ver)

    return existing


def check_github_releases(repo: str, arch: str) -> Dict[str, set]:
    """Find versions that are already published in GitHub Releases."""
    existing = {"desktop": set(), "ide": set()}
    if not repo:
        return existing

    url = f"https://api.github.com/repos/{repo}/releases?per_page=100"
    headers = {"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    deb_arch = "amd64" if arch in ("amd64", "x86_64") else "arm64"
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            for item in data:
                for asset in item.get("assets", []):
                    fname = asset.get("name", "")
                    m = re.match(rf"^(antigravity|antigravity-ide)_([0-9\.]+)(?:-[0-9]+)?_{re.escape(deb_arch)}\.deb$", fname)
                    if m:
                        pkg, ver = m.group(1), m.group(2)
                        prod = "ide" if pkg == "antigravity-ide" else "desktop"
                        existing[prod].add(ver)
    except Exception as e:
        print(f"[WARN] Failed fetching releases from {repo}: {e}", file=sys.stderr)

    return existing


def main():
    parser = argparse.ArgumentParser(description="Discover Google Antigravity versions.")
    parser.add_argument("--arch", default="amd64", choices=["amd64", "arm64", "x86_64", "aarch64"], help="Target architecture")
    parser.add_argument("--product", default="all", choices=["desktop", "ide", "all"], help="Product to discover")
    parser.add_argument("--mode", default="all", choices=["all", "latest"], help="Discover all historical versions or only latest")
    parser.add_argument("--output-dir", default="/output", help="Directory where .deb files are stored")
    parser.add_argument("--github-repo", default=os.environ.get("GITHUB_REPOSITORY", ""), help="Check published releases in GitHub repo")
    parser.add_argument("--json", action="store_true", help="Output raw JSON")
    args = parser.parse_args()

    norm_arch = "amd64" if args.arch in ("amd64", "x86_64") else "arm64"
    live = discover_live_versions(norm_arch)
    existing_local = check_existing_debs(args.output_dir, norm_arch)
    existing_gh = check_github_releases(args.github_repo, norm_arch) if args.github_repo else {"desktop": set(), "ide": set()}

    existing = {
        "desktop": existing_local["desktop"] | existing_gh["desktop"],
        "ide": existing_local["ide"] | existing_gh["ide"]
    }

    to_process = {"desktop": [], "ide": []}

    if args.mode == "latest":
        for prod in ("desktop", "ide"):
            if prod in live:
                to_process[prod].append(live[prod])
    else:
        historical = discover_historical_versions(norm_arch)
        for prod in ("desktop", "ide"):
            ver_map = {item["version"]: item for item in historical.get(prod, [])}
            if prod in live:
                ver_map[live[prod]["version"]] = live[prod]
            def sort_key(x):
                parts = []
                for p in x["version"].split("."):
                    parts.append(int(p) if p.isdigit() else p)
                return parts
            to_process[prod] = sorted(ver_map.values(), key=sort_key)

    output_data = {"arch": norm_arch, "products": {}}
    for prod in ("desktop", "ide"):
        if args.product != "all" and args.product != prod:
            continue
        items = []
        for item in to_process[prod]:
            built = item["version"] in existing[prod]
            is_latest = (prod in live and live[prod]["version"] == item["version"])
            items.append({
                "product": prod,
                "pkg_name": "antigravity" if prod == "desktop" else "antigravity-ide",
                "version": item["version"],
                "build_id": item["build_id"],
                "url": item["url"],
                "is_latest": is_latest,
                "already_built": built,
                "needs_build": not built
            })
        output_data["products"][prod] = items

    if args.json:
        print(json.dumps(output_data, indent=2))
    else:
        print(f"=== Antigravity Version Status ({norm_arch}) ===")
        for prod, items in output_data["products"].items():
            name = "Antigravity 2.0 Desktop" if prod == "desktop" else "Antigravity IDE"
            print(f"\n[{name}]")
            if not items:
                print("  No versions detected.")
                continue
            for it in items:
                status = "[ALREADY BUILT]" if it["already_built"] else "[NEEDS BUILD]"
                badge = "[LATEST] " if it["is_latest"] else "         "
                print(f"  {badge}{status:16} v{it['version']} ({it['build_id']})")
                print(f"           URL: {it['url']}")


if __name__ == "__main__":
    main()
