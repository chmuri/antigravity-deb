#!/usr/bin/env python3
"""
make_release_notes.py - Generates formatted GitHub Release notes markdown.
"""
import sys

if len(sys.argv) < 8:
    print(f"Usage: {sys.argv[0]} <title> <deb_name> <sha256> <build_id> <url> <pkg> <output_file>", file=sys.stderr)
    sys.exit(1)

title, deb_name, sha256, build_id, url, pkg, out_path = sys.argv[1:8]

notes = f"""### {title} (Debian/Ubuntu package)

- **Package**: `{deb_name}`
- **Architecture**: `amd64`
- **SHA256**: `{sha256}`
- **Upstream Build**: `{build_id}`
- **Official Source**: [{url}]({url})

#### Installation via APT
```bash
# Add repository
curl -fsSL https://chmuri.github.io/antigravity-deb/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/antigravity.gpg
echo "deb [signed-by=/etc/apt/keyrings/antigravity.gpg] https://github.com/chmuri/antigravity-deb/releases/download/stable ./" | sudo tee /etc/apt/sources.list.d/antigravity.list
sudo apt-get update
sudo apt-get install -y {pkg}
```

#### Direct Download
Download the `.deb` asset attached below and install with:
```bash
sudo apt install ./{deb_name}
```
"""

with open(out_path, "w", encoding="utf-8") as f:
    f.write(notes)

print(f"[INFO] Generated release notes in {out_path}")
