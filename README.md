# Google Antigravity - Debian/Ubuntu APT Repository

[![Build and Publish APT Packages](https://github.com/chmuri/antigravity-deb/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/chmuri/antigravity-deb/actions/workflows/build-and-publish.yml)
[![GitHub Releases](https://img.shields.io/github/v/release/chmuri/antigravity-deb?include_prereleases&color=blue&label=Latest%20Release)](https://github.com/chmuri/antigravity-deb/releases)
[![APT Repository](https://img.shields.io/badge/APT%20Repository-GitHub%20Pages-informational)](https://chmuri.github.io/antigravity-deb/)
[![Architectures](https://img.shields.io/badge/Architectures-amd64-success)](#supported-architectures)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Official-grade, automated Debian and Ubuntu package repository for **Google Antigravity 2.0** and **Google Antigravity IDE**.

Packages are automatically discovered, built from official Google distribution tarballs, cryptographically signed with GPG, and synchronized to this repository **twice daily** (at 04:00 and 16:00 UTC) via GitHub Actions.

---

## 🚀 Quick Install (APT Repository)

Add the GPG key and APT repository to your Debian/Ubuntu machine using modern, secure keyring standards:

```bash
# 1. Install prerequisites
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg

# 2. Add the repository GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://chmuri.github.io/antigravity-deb/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/antigravity.gpg
sudo chmod a+r /etc/apt/keyrings/antigravity.gpg

# 3. Add the APT source repository (stable main)
echo "deb [signed-by=/etc/apt/keyrings/antigravity.gpg] https://chmuri.github.io/antigravity-deb stable main" | sudo tee /etc/apt/sources.list.d/antigravity.list

# 4. Update index and install
sudo apt-get update
sudo apt-get install -y antigravity antigravity-ide
```

### ⚡ One-Liner Setup
```bash
curl -fsSL https://chmuri.github.io/antigravity-deb/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/antigravity.gpg && sudo chmod a+r /etc/apt/keyrings/antigravity.gpg && echo "deb [signed-by=/etc/apt/keyrings/antigravity.gpg] https://chmuri.github.io/antigravity-deb stable main" | sudo tee /etc/apt/sources.list.d/antigravity.list && sudo apt-get update
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

If you prefer installing individual `.deb` packages without adding the APT repository:

1. Browse to [GitHub Releases](https://github.com/chmuri/antigravity-deb/releases).
2. Download the desired `.deb` package (e.g. `antigravity_2.12.2_amd64.deb` or `antigravity-ide_2.5.5_amd64.deb`).
3. Install using `apt`:
   ```bash
   sudo apt install ./antigravity_*_amd64.deb
   sudo apt install ./antigravity-ide_*_amd64.deb
   ```

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
        ├─► GitHub Releases     (Stores heavy .deb binary assets & SHA256 checksums)
        ├─► update_repo.sh       (Builds Packages.gz, Release, signs InRelease with GPG)
        └─► GitHub Pages (gh-pages) (Serves signed APT repository indexes & public.key)
                │
                ▼
Ubuntu / Debian Clients (apt-get update && apt-get install antigravity)
```

1. **Version Discovery**: `discover_versions.py` parses `https://antigravity.google/download` and bundle JavaScript for official Google releases. It also indexes historical versions using Wayback Machine CDX API snapshots.
2. **Debian Packaging**: `build_deb.sh` extracts upstream tarballs, stages application files into `/opt/antigravity*`, sets `chrome-sandbox` SUID `4755` permissions, extracts high-resolution icons from `app.asar`, installs desktop entry files into `/usr/share/applications/`, and compiles `.deb` archives with `dpkg-deb`.
3. **Release Hosting**: Due to GitHub Pages file size limits (100 MB max), packages (130–180 MB) are published to **GitHub Releases**. The APT repository `Packages` index references direct HTTPS asset download URLs.
4. **Signature & Distribution**: `update_repo.sh` generates `Packages.gz`, `Packages.xz`, `Release`, signs `InRelease` with GPG, and deploys metadata to GitHub Pages.

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
The local APT repository will be accessible at `http://localhost:8080/`.

---

## 💻 Supported Operating Systems

- **Ubuntu**: 20.04 LTS (Focal), 22.04 LTS (Jammy), 24.04 LTS (Noble), and newer
- **Debian**: 11 (Bullseye), 12 (Bookworm), and newer
- **Linux Mint**, **Pop!_OS**, **Elementary OS**, and other Debian-based distributions

---

## 📄 License

- The build scripts, GitHub Actions workflows, and packaging automation in this repository are licensed under the [MIT License](LICENSE).
- **Google Antigravity**, **Antigravity IDE**, and associated trademarks and proprietary binaries are copyright **Google LLC**.
