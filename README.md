# Google Antigravity - Debian/Ubuntu APT Repository

[![Build and Publish APT Packages](https://github.com/chmuri/antigravity-deb/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/chmuri/antigravity-deb/actions/workflows/build-and-publish.yml)
[![GitHub Releases](https://img.shields.io/github/v/release/chmuri/antigravity-deb?include_prereleases&color=blue&label=Latest%20Release)](https://github.com/chmuri/antigravity-deb/releases)
[![APT Repository](https://img.shields.io/badge/APT%20Repository-GitHub%20Pages-informational)](https://chmuri.github.io/antigravity-deb/)
[![Architectures](https://img.shields.io/badge/Architectures-amd64-success)](#supported-architectures)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Automated Debian and Ubuntu package repository (unofficial) for **Google Antigravity 2.0** and **Google Antigravity IDE**, built from official Google distribution tarballs.

Packages are automatically discovered, built from official Google distribution tarballs, cryptographically signed with GPG, and synchronized to this repository **twice daily** (at 04:00 and 16:00 UTC) via GitHub Actions.

---

## 🚀 Quick Install (APT Repository)

Add the GPG key and APT repository to your Debian/Ubuntu machine using modern, secure keyring standards.

> **How the source is described**: the repository is a *flat* rolling repository
> (`Suites: ./`) hosted on GitHub Releases — this is required because the `.deb`
> packages are 130–180 MB and GitHub Pages only accepts files up to 100 MB. See
> [Architecture](#-architecture--how-it-works) for details.

```bash
# 1. Install prerequisites
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg

# 2. Add the repository GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://chmuri.github.io/antigravity-deb/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/antigravity.gpg
sudo chmod a+r /etc/apt/keyrings/antigravity.gpg

# 3. Add the APT source (deb822 format, with a human-readable description)
sudo tee /etc/apt/sources.list.d/antigravity.sources > /dev/null <<'EOF'
Types: deb
URIs: https://github.com/chmuri/antigravity-deb/releases/download/stable
Suites: ./
Signed-By: /etc/apt/keyrings/antigravity.gpg
Description: Google Antigravity (unofficial) - Antigravity 2.0 AI desktop agent and Antigravity IDE
EOF

# 4. Update index and install
sudo apt-get update
sudo apt-get install -y antigravity antigravity-ide
```

<details>
<summary><b>Classic one-line <code>.list</code> alternative</b></summary>

```bash
echo "deb [signed-by=/etc/apt/keyrings/antigravity.gpg] https://github.com/chmuri/antigravity-deb/releases/download/stable ./" | sudo tee /etc/apt/sources.list.d/antigravity.list
```
</details>

### ⚡ One-Liner Setup
Prefer the deb822 source above (it carries the description). A minimal one-liner that uses the classic `.list` syntax:
```bash
curl -fsSL https://chmuri.github.io/antigravity-deb/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/antigravity.gpg && sudo chmod a+r /etc/apt/keyrings/antigravity.gpg && echo "deb [signed-by=/etc/apt/keyrings/antigravity.gpg] https://github.com/chmuri/antigravity-deb/releases/download/stable ./" | sudo tee /etc/apt/sources.list.d/antigravity.list && sudo apt-get update
```

---

## 📦 Available Packages

| Package Name | Application | Description | Launcher Command |
|---|---|---|---|
| `antigravity` | **Google Antigravity 2.0** | Autonomous AI agent desktop application with sandbox isolation and system tray support. | `antigravity` |
| `antigravity-ide` | **Google Antigravity IDE** | Next-generation agentic IDE with workspace context and GNOME Files (Nautilus) integration. | `antigravity-ide` |

---

## 🔄 Automatic System Updates

Once the repository is added, Antigravity stays up-to-date alongside your standard system software:

```bash
sudo apt-get update
sudo apt-get --only-upgrade install antigravity antigravity-ide
```

---

## 📥 Direct `.deb` Manual Downloads

All `.deb` packages (every published version, for both `antigravity` and `antigravity-ide`) are stored on the single rolling [`stable` GitHub Release](https://github.com/chmuri/antigravity-deb/releases/tag/stable). If you prefer installing individual `.deb` files without adding the APT repository:

```bash
# Examples — pick the exact file you want from the release page
curl -fLO https://github.com/chmuri/antigravity-deb/releases/download/stable/antigravity_2.12.2_amd64.deb
curl -fLO https://github.com/chmuri/antigravity-deb/releases/download/stable/antigravity-ide_2.5.5_amd64.deb

sudo apt install ./antigravity_*_amd64.deb
sudo apt install ./antigravity-ide_*_amd64.deb
```

SHA256 checksums are listed on the release page for each asset.

---

## 🔐 Security & GPG Key Verification

All repository metadata files (`InRelease`, `Release.gpg`) are cryptographically signed using GPG:

- **Key ID**: `18EBB53D09F5866F73EB94CF81435F158DF507A0`
- **Key Fingerprint**: `18EB B53D 09F5 866F 73EB  94CF 8143 5F15 8DF5 07A0`
- **Public Key**: Available at [`https://chmuri.github.io/antigravity-deb/public.key`](https://chmuri.github.io/antigravity-deb/public.key) or in the repository root as [`public.key`](public.key).

To inspect the public key fingerprint locally:
```bash
curl -fsSL https://chmuri.github.io/antigravity-deb/public.key | gpg --show-keys
```

---

## 🏗️ Architecture & How It Works

```
Google Upstream (antigravity.google/download)
        │
        ▼
GitHub Actions (Runs 2x daily: 04:00 & 16:00 UTC)
        ├─► discover_versions.py (Detects new versions & historical releases)
        ├─► build_deb.sh         (Packages .deb according to Debian policy)
        ├─► update_repo.sh       (Builds flat Packages/Release, signs InRelease with GPG)
        └─► Single rolling GitHub Release tag "stable"
               (Serves all .deb files + signed flat repository indexes)
                │
                ▼
Ubuntu / Debian Clients (apt-get update && apt-get install antigravity)
```

1. **Version Discovery**: `discover_versions.py` parses `https://antigravity.google/download` and bundle JavaScript for official Google releases. It also indexes historical versions using Wayback Machine CDX API snapshots.
2. **Debian Packaging**: `build_deb.sh` extracts upstream tarballs, stages application files into `/opt/antigravity*`, sets `chrome-sandbox` SUID `4755` permissions, extracts high-resolution icons from `app.asar`, installs desktop entry files into `/usr/share/applications/`, and compiles `.deb` archives with `dpkg-deb`.
3. **Release Hosting**: GitHub Pages rejects files over 100 MB, so the packages (130–180 MB) are hosted as **GitHub Release assets**. Because GitHub Release assets are stored flat (no subdirectories), the APT repository is published as a **flat repository** on a stable, rolling release tag (`stable`). `update_repo.sh` writes a relative `Filename:` (the `.deb` basename) into `Packages`, so `apt` resolves every download against the release-tag base URI — no cross-host URL tricks required.
4. **Signature & Distribution**: `update_repo.sh` generates `Packages`, `Packages.gz`, `Release`, and signs `InRelease` with GPG. Everything (`.deb` files plus signed indexes) is uploaded to the rolling `stable` release tag — the index and binaries always stay on the same host.
5. **Public Key**: `public.key` and a human-friendly landing page are published to **GitHub Pages** for keyring setup and browsing.

---

## 🐳 Local Docker Usage

You can also run the builder or a local APT repository mirror on your own machine using Docker:

### 1. Build the Docker Image
```bash
docker build -t antigravity-deb-builder .
```

### 2. Check for Upstream Releases
```bash
docker run --rm antigravity-deb-builder check
```

### 3. Build All Packages Locally into `./dist`
```bash
docker run --rm -v $(pwd)/dist:/output antigravity-deb-builder build-all
```

### 4. Run Local APT HTTP Mirror (Docker Compose)
```bash
docker compose up -d
```
The local APT repository will be accessible at `http://localhost:8080/`. To test it as a flat repository:
```bash
echo "deb [trusted=yes] http://localhost:8080/ ./" | sudo tee /etc/apt/sources.list.d/antigravity-local.list
sudo apt-get update && sudo apt-get install -y antigravity
```

---

## 💻 Supported Operating Systems

- **Ubuntu**: 20.04 LTS (Focal), 22.04 LTS (Jammy), 24.04 LTS (Noble), and newer
- **Debian**: 11 (Bullseye), 12 (Bookworm), and newer
- **Linux Mint**, **Pop!_OS**, **Elementary OS**, and other Debian-based distributions

---

## 📄 License

- The build scripts, GitHub Actions workflows, and packaging automation in this repository are licensed under the [MIT License](LICENSE).
- **Google Antigravity**, **Antigravity IDE**, and associated trademarks and proprietary binaries are copyright **Google LLC**.
