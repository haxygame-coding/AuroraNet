# AuroraNet

<p align="center">
  <img src="https://raw.githubusercontent.com/haxygame-coding/AuroraNet/main/assets/logo.png" width="140" alt="AuroraNet Logo"/>
</p>

<p align="center">
  <strong>Open-source self-hosted mesh networking powered by WireGuard.</strong>
</p>

<p align="center">
  Lightweight and secure peer-to-peer networking infrastructure.
</p>

<p align="center">
  <a href="https://aurora-net.org">https://aurora-net.org</a>
</p>

---

# Overview

AuroraNet is an open-source, self-hosted mesh networking platform built on top of WireGuard. It enables devices to communicate securely over the internet as if they were connected to the same local network.

AuroraNet is designed for developers, infrastructure engineers, homelab environments, and organizations that require full control over their networking stack without depending on third-party VPN providers.

The project focuses on simplicity, performance, transparency, and infrastructure ownership.

---

# Features

## Networking

* WireGuard-based encrypted tunnels
* Peer-to-peer mesh networking
* NAT traversal support
* Lightweight networking agent
* Secure authentication and peer management
* Cross-platform architecture

## Dashboard

* Web-based administration interface
* Device and peer management
* Network monitoring
* Configuration management
* Real-time connection overview

## Infrastructure

* Fully self-hosted control plane
* Modular backend architecture
* REST API support
* Scalable deployment model
* Lightweight resource usage

---

# Architecture

```text id="8x5n4v"
AuroraNet/
├── agent/                 # Networking agent running on clients
├── core/                  # Backend services and APIs
├── dashboard/             # Web administration dashboard
├── install_server.sh      # Automated installation script
└── README.md
```

## Components

### `agent`

The networking agent is responsible for:

* WireGuard tunnel management
* Peer synchronization
* Secure device communication
* Connectivity handling

### `core`

The backend core provides:

* API services
* Authentication
* Peer coordination
* Network state management
* Infrastructure orchestration

### `dashboard`

The dashboard provides a web interface for:

* Managing devices
* Monitoring peers
* Viewing network status
* Configuring infrastructure

---

# Why AuroraNet

AuroraNet provides the advantages of modern mesh networking solutions while remaining fully open and self-hosted.

| Feature                  | AuroraNet | Tailscale | ZeroTier |
| ------------------------ | --------- | --------- | -------- |
| Fully self-hosted        | Yes       | Partial   | Partial  |
| Open-source              | Yes       | Partial   | Partial  |
| WireGuard-based          | Yes       | Yes       | No       |
| Infrastructure ownership | Yes       | No        | No       |
| Lightweight architecture | Yes       | Yes       | Moderate |

---

# Installation

## Requirements

* Linux server (Ubuntu recommended)
* WireGuard
* Go 1.22+
* Node.js 20+
* Docker (optional)

---

## Quick Installation

```bash id="u0k8ce"
git clone https://github.com/haxygame-coding/AuroraNet.git
cd AuroraNet

chmod +x install_server.sh
./install_server.sh
```

---

# Development Setup

## Clone the Repository

```bash id="wn9i67"
git clone https://github.com/haxygame-coding/AuroraNet.git
cd AuroraNet
```

---

## Backend

```bash id="k5bj1t"
cd core
go mod tidy
go run .
```

---

## Dashboard

```bash id="z57fgf"
cd dashboard
npm install
npm run dev
```

---

## Agent

```bash id="t5grfe"
cd agent
go run .
```

---

# Configuration

AuroraNet uses environment-based configuration.

Example configuration:

```env id="r7v0l8"
AURORA_HOST=0.0.0.0
AURORA_PORT=8080

JWT_SECRET=change_this_secret
DATABASE_URL=postgres://user:password@localhost/auroranet

WIREGUARD_INTERFACE=wg0
```

---

# Security

AuroraNet is built around modern security principles:

* End-to-end encrypted tunnels
* WireGuard cryptography
* Secure peer authentication
* Self-hosted infrastructure
* Minimal attack surface
* Controlled network access

---

# Roadmap

Planned features include:

* Multi-user support
* Access control lists (ACL)
* Role-based permissions
* Mobile clients
* Relay servers
* Kubernetes integration
* High-availability deployments
* SSO authentication
* Integrated DNS management
* Observability and metrics

---

# Contributing

Contributions are welcome.

## Workflow

1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push to your branch
5. Open a Pull Request

---

# License

AuroraNet is licensed under the MIT License.

See the `LICENSE` file for more information.

---

# Philosophy

AuroraNet is built around a simple philosophy:

* Open infrastructure
* Transparent networking
* Full ownership
* High performance
* Lightweight deployment
* Developer-focused tooling

---

# Acknowledgements

AuroraNet is inspired by projects and technologies such as:

* WireGuard
* Tailscale
* ZeroTier
* Netmaker
* Nebula

---

# Support

For bug reports, feature requests, or contributions:

* Open an issue on GitHub
* Submit a Pull Request
* Participate in discussions

---

<p align="center">
AuroraNet — Secure and self-hosted mesh networking.
</p>
