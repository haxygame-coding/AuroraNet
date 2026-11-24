# AuroraNet — installation

AuroraNet is a self-hosted WireGuard-based overlay network. This document covers
the released artifacts.

## Supported platforms

| Platform | Architecture | Artifact |
| --- | --- | --- |
| Linux — Debian/Ubuntu | amd64 | `.deb` |
| Linux — Arch | x86_64 | `.pkg.tar.zst` |
| Linux — other distributions | amd64, arm64, 386 | `.tar.gz` |
| Windows 10/11 | x64 | `.msi` |
| Server (Docker) | linux/amd64 | GHCR images |

The client is CLI-only: no desktop GUI is shipped. macOS, FreeBSD, Linux on
armv6/armv7 and Windows on ARM are not built or released. The `install.sh`
script refuses those systems instead of downloading a missing archive, and the
CI build matrix in `.github/workflows/ci.yml` covers exactly the targets above.

## Server (Docker Compose)

Requirements: a Linux host (Ubuntu 22.04/24.04 or Debian 12/13, amd64), a public
FQDN pointing at the host, ports 80/443 TCP and 3478 UDP open, Docker Engine with
the Compose plugin.

```bash
curl -fsSL https://raw.githubusercontent.com/haxygame-coding/auroranet/main/infrastructure_files/getting-started.sh -o getting-started.sh
chmod +x getting-started.sh
sudo ./getting-started.sh
```

The script asks for the FQDN and the Let's Encrypt email. Both can be passed
non-interactively:

```bash
sudo AURORANET_DOMAIN=vpn.aurora-net.org \
     AURORANET_EMAIL=admin@aurora-net.org \
     AURORANET_NON_INTERACTIVE=true \
     ./getting-started.sh
```

Images pulled by the generated compose file:

- `ghcr.io/haxygame-coding/auroranet-server:latest`
- `ghcr.io/haxygame-coding/auroranet-dashboard:latest`
- `ghcr.io/haxygame-coding/auroranet-proxy:latest` (only when the proxy is enabled)

The dashboard and the management API are served from the same FQDN over 443.

## Linux client

Debian/Ubuntu:

```bash
sudo apt install ./auroranet_0.71.6_amd64.deb
sudo auroranet up --setup-key <KEY> --management-url https://vpn.aurora-net.org
```

Arch:

```bash
sudo pacman -U auroranet-0.71.6-1-x86_64.pkg.tar.zst
sudo auroranet up --setup-key <KEY> --management-url https://vpn.aurora-net.org
```

Other distributions (binary archive):

```bash
tar -xzf auroranet_0.71.6_linux_amd64.tar.gz
sudo install -m 0755 auroranet /usr/local/bin/auroranet
sudo auroranet service install
sudo auroranet up --setup-key <KEY> --management-url https://vpn.aurora-net.org
```

The package installs the `auroranet` binary and the `auroranet.service` systemd
unit, enabled on install. Files live in `/etc/auroranet` and `/var/lib/auroranet`.

## Windows client

Windows 10/11 x64: install `auroranet_0.71.6_windows_amd64.msi`, then run in an
elevated PowerShell:

```powershell
auroranet up --setup-key <KEY> --management-url https://vpn.aurora-net.org
```

The MSI installs the CLI and registers the `AuroraNet` Windows service (`wintun.dll`
is bundled). The MSI is not Authenticode-signed, so SmartScreen shows a warning:
choose *More info* → *Run anyway*.

`--management-url` is required while the client's built-in default
(`https://api.aurora-net.org`) does not resolve. Without it, `auroranet up`
cannot reach the self-hosted server.

## Verifying downloads

Every artifact is listed in `SHA256SUMS`, which is signed with the AuroraNet
release key:

```bash
gpg --import auroranet-release-key.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

The key fingerprint is published in the release notes.
