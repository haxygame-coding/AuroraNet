#!/usr/bin/env bash

cat >&2 <<'EOF'
ERROR: This legacy installation script has been retired and no longer runs.

Dex support is not deprecated. For new deployments, use getting-started.sh:

https://docs.aurora-net.org/selfhosted/selfhosted-quickstart

The current installer includes AuroraNet's embedded Dex-based identity provider.
Local users and external identity providers can be managed through the
AuroraNet Dashboard:

https://docs.aurora-net.org/selfhosted/identity-providers/local

This compatibility notice will be removed in AuroraNet v0.80.
EOF

exit 1
