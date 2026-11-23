#!/usr/bin/env bash

cat >&2 <<'EOF'
ERROR: This legacy installation script has been retired and no longer runs.

Zitadel support and existing Zitadel deployments are not deprecated.

For new deployments, use getting-started.sh:

https://docs.aurora-net.org/selfhosted/selfhosted-quickstart

The current installer includes AuroraNet's embedded Dex-based identity provider.
Zitadel can be added as an external identity provider directly through the
AuroraNet Dashboard:

https://docs.aurora-net.org/selfhosted/identity-providers/zitadel

Standalone Zitadel and other custom identity-provider deployments remain
supported through the advanced guide:

https://docs.aurora-net.org/selfhosted/selfhosted-guide

This compatibility notice will be removed in AuroraNet v0.80.
EOF

exit 1
