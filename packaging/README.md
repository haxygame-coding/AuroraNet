# AuroraNet — installation

AuroraNet is a self-hosted WireGuard-based overlay network. This document covers
the released artifacts.

## Server (Docker Compose)

Requirements: a Linux host (Ubuntu 22.04/24.04 or Debian 12/13, amd64), a public
FQDN pointing at the host, ports 80/443 TCP and 3478 UDP open, Docker Engine with
the Compose plugin.

```bash
curl -fsSL https://raw.githubusercontent.com/haxygame/auroranet/main/infrastructure_files/getting-started.sh -o getting-started.sh
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

- `ghcr.io/haxygame/auroranet-server:latest`
- `ghcr.io/haxygame/auroranet-dashboard:latest`
- `ghcr.io/haxygame/auroranet-proxy:latest` (only when the proxy is enabled)

## Linux client

Debian/Ubuntu:

```bash
sudo apt install ./auroranet_1.0.0_amd64.deb
sudo auroranet up --setup-key <KEY>
```

Arch:

```bash
sudo pacman -U auroranet-1.0.0-1-x86_64.pkg.tar.zst
sudo auroranet up --setup-key <KEY>
```

Both packages install the `auroranet` binary and the `auroranet.service` systemd
unit, enabled on install. Files live in `/etc/auroranet` and `/var/lib/auroranet`.

## Windows client

Windows 10/11 x64: install `auroranet_1.0.0_windows_amd64.msi`, then run:

```powershell
auroranet up --setup-key <KEY>
```

The MSI installs the CLI and registers the `AuroraNet` Windows service. The MSI is
not code-signed in v1, so SmartScreen shows a warning: choose *More info* →
*Run anyway*.

## Verifying downloads

Every artifact is listed in `SHA256SUMS`, which is signed with the AuroraNet
release key:

```bash
gpg --import auroranet-release-key.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

The key fingerprint is published in the release notes.
