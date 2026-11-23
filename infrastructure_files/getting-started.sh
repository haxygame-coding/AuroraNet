#!/bin/bash

set -e

# AuroraNet Getting Started with Embedded IdP (Dex)
# This script sets up AuroraNet with the embedded Dex identity provider
# No separate Dex container or reverse proxy needed - IdP is built into management server

# Sed pattern to strip base64 padding characters
SED_STRIP_PADDING='s/=//g'

# Constants for repeated string literals
readonly MSG_STARTING_SERVICES="\nStarting AuroraNet services\n"
readonly MSG_DONE="\nDone!\n"
readonly MSG_NEXT_STEPS="Next steps:"
readonly MSG_SEPARATOR="=========================================="

############################################
# Utility Functions
############################################

check_docker_sock_perms() {
  local sock="${DOCKER_HOST:-unix:///var/run/docker.sock}"
  sock="${sock#unix://}"

  if [[ ! -S "$sock" ]]; then
    return 0
  fi

  if [[ ! -r "$sock" ]] || [[ ! -w "$sock" ]]; then
    local group
    if [[ "${OSTYPE}" == "darwin"* ]]; then
      group="$(stat -f '%Sg' "$sock")"
    else
      group="$(stat -c '%G' "$sock")"
    fi

    echo "Cannot access Docker socket: $sock" > /dev/stderr
    echo "" > /dev/stderr
    echo "Socket permissions:" > /dev/stderr
    ls -l "$sock" > /dev/stderr
    echo "" > /dev/stderr

    if [[ "$group" == "docker" ]]; then
      echo "Your user may need to be added to the '$group' group:" > /dev/stderr
      echo "  sudo usermod -aG $group \"$USER\"" > /dev/stderr
      echo "Then log out and back in, or run this for the current shell:" > /dev/stderr
      echo "  newgrp $group" > /dev/stderr
      echo "Note: newgrp is temporary; usermod is the permanent group change." > /dev/stderr
    else
      echo "The Docker socket is owned by the '$group' group, which is not the standard 'docker' group." > /dev/stderr
      echo "For safety, this script will not suggest adding your user to '$group'." > /dev/stderr
      echo "Instead, either run this script with appropriate privileges (for example, via sudo) or follow Docker's post-install steps to configure access via the 'docker' group:" > /dev/stderr
      echo "  https://docs.docker.com/engine/install/linux-postinstall/" > /dev/stderr
    fi

    exit 1
  fi
  return 0
}

check_docker_compose() {
  if ! command -v docker &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "Docker is not installed or not in PATH. Please follow the steps from the official guide: https://docs.docker.com/engine/install/" > /dev/stderr
    exit 1
  fi

  if docker compose version &> /dev/null; then
    echo "docker compose"
    return
  fi
  if command -v docker-compose &> /dev/null && docker-compose version &> /dev/null; then
    echo "docker-compose"
    return
  fi

  echo "Docker Compose is not installed or not in PATH. Please follow the steps from the official guide: https://docs.docker.com/compose/install/" > /dev/stderr
  exit 1
}

check_jq() {
  if ! command -v jq &> /dev/null
  then
    echo "jq is not installed or not in PATH, please install with your package manager. e.g. sudo apt install jq" > /dev/stderr
    exit 1
  fi
  return 0
}

check_traefik_image() {
  local image="${TRAEFIK_IMAGE##*/}" major minor patch

  # A version tag cannot establish which release a digest points to.
  if [[ "$TRAEFIK_IMAGE" == *@* ||
    ! "$image" =~ ^[^:@]+:v?([0-9]+)(\.([0-9]+)(\.([0-9]+))?)?$ ]]; then
    echo "Cannot verify TRAEFIK_IMAGE=$TRAEFIK_IMAGE." >&2
    echo "Use a numeric Traefik version tag (v3.7.13 or newer) without a digest." >&2
    return 1
  fi
  major=$((10#${BASH_REMATCH[1]}))
  minor=$((10#${BASH_REMATCH[3]:-0}))
  patch=$((10#${BASH_REMATCH[5]:-0}))
  if (( major < 3 || (major == 3 && minor < 7) || (major == 3 && minor == 7 && patch < 13) )); then
    echo "TRAEFIK_IMAGE=$TRAEFIK_IMAGE is incompatible with this configuration." >&2
    echo "Use Traefik v3.7.13 or newer for aliasHeadersStrategy and its header-sanitization fix." >&2
    return 1
  fi
  return 0
}

get_main_ip_address() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    interface=$(route -n get default | grep 'interface:' | awk '{print $2}')
    ip_address=$(ifconfig "$interface" | grep 'inet ' | awk '{print $2}')
  else
    interface=$(ip route | grep default | awk '{print $5}' | head -n 1)
    ip_address=$(ip addr show "$interface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
  fi

  echo "$ip_address"
  return 0
}

check_nb_domain() {
  local domain="$1"

  if [[ -z "$domain" ]]; then
    echo "The AURORANET_DOMAIN variable cannot be empty." > /dev/stderr
    return 1
  fi
  if [[ "$domain" == "use-ip" ]]; then
    return 0
  fi
  if [[ "$domain" == "auroranet.example.com" ]]; then
    echo "The AURORANET_DOMAIN cannot be auroranet.example.com" > /dev/stderr
    return 1
  fi
  if [[ "$domain" =~ ^[0-9.]+$ ]]; then
    echo "'$domain' is an IP address. Use 'use-ip' to install on this host's IP over HTTP, or an FQDN to get a TLS certificate." > /dev/stderr
    return 1
  fi
  if [[ ! "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
    echo "'$domain' is not a valid FQDN. It needs at least one dot (e.g. vpn.aurora-net.org), with no scheme, port or trailing dot." > /dev/stderr
    return 1
  fi
  return 0
}

check_domain_resolves() {
  local domain="$1"
  if command -v getent &> /dev/null && getent hosts "$domain" &> /dev/null; then return 0; fi
  if command -v host &> /dev/null && host "$domain" &> /dev/null; then return 0; fi
  if command -v dig &> /dev/null && [[ -n "$(dig +short "$domain" 2>/dev/null)" ]]; then return 0; fi
  if command -v nslookup &> /dev/null && nslookup "$domain" &> /dev/null; then return 0; fi
  return 1
}

# Non-interactive configuration
# ------------------------------
# Every prompt below can be pre-answered with an environment variable, so the
# script runs unattended (cloud-init, CI, Terraform, curl | bash). resolve()
# is the single place that decides env var vs prompt vs default; the read_*
# helpers stay pure prompts.
#
# Supported env vars:
#   AURORANET_DOMAIN                    domain/FQDN (required)
#   AURORANET_EMAIL         ACME email (required for built-in Traefik)
#   AURORANET_AGENT_NETWORK             true enables the agent-network preset
#   AURORANET_REVERSE_PROXY_TYPE        0-5 (default 0 = built-in Traefik)
#   AURORANET_ENABLE_PROXY              true/false (default false)
#   AURORANET_ENABLE_CROWDSEC           true/false (default false)
#   AURORANET_ENABLE_CROWDSEC_APPSEC    true/false (default false; requires AURORANET_ENABLE_CROWDSEC=true,
#                                     which needs built-in Traefik (type 0) and AURORANET_ENABLE_PROXY=true)
#   AURORANET_TRAEFIK_EXTERNAL_NETWORK  external-Traefik network (type 1)
#   AURORANET_TRAEFIK_ENTRYPOINT        external-Traefik entrypoint (type 1, default websecure)
#   AURORANET_TRAEFIK_CERTRESOLVER      external-Traefik cert resolver (type 1)
#   AURORANET_BIND_LOCALHOST_ONLY       true/false (default true, types 2-5)
#   AURORANET_EXTERNAL_PROXY_NETWORK    docker network to join (types 2-4)
#   AURORANET_TRUSTED_PEERS             reverse proxy address management sees (default: built-in Traefik's IP, empty for types 1-5)
#   AURORANET_NON_INTERACTIVE           true forces unattended mode even with a TTY

# tty_available succeeds only when we may prompt: never when the operator has
# set AURORANET_NON_INTERACTIVE=true, otherwise only when /dev/tty can actually
# be opened. A PTY can be attached in automation (CI runners, some
# provisioners), so the env override is the authoritative signal and the
# /dev/tty probe is the fallback. /dev/tty is a world-rw device node even with
# no terminal, so a permission test ([ -r ]) is not enough - we must open it.
tty_available() {
  [[ "${AURORANET_NON_INTERACTIVE:-}" == "true" ]] && return 1
  { true < /dev/tty; } 2>/dev/null
}

# resolve ENV_VAR_NAME DEFAULT PROMPT_FN [prompt args...]
#   env var set and non-empty -> its value
#   interactive               -> PROMPT_FN "$@" (prompt behavior unchanged)
#   otherwise                 -> DEFAULT, or abort when DEFAULT is "required"
resolve() {
  local env_name="$1" default="$2" prompt_fn="$3"
  shift 3
  local env_value="${!env_name:-}"
  if [[ -n "$env_value" ]]; then
    echo "$env_value"
  elif tty_available; then
    "$prompt_fn" "$@"
  elif [[ "$default" == "required" ]]; then
    echo "$env_name is required for a non-interactive install." > /dev/stderr
    exit 1
  else
    echo "$default"
  fi
  return 0
}

validate_boolean_env() {
  local env_name="$1"
  case "${!env_name:-}" in
    "" | true | false) return 0 ;;
    *)
      echo "$env_name must be true or false." > /dev/stderr
      exit 1
      ;;
  esac
}

read_nb_domain() {
  READ_AURORANET_DOMAIN=""
  echo -n "Enter the domain you want to use for AuroraNet (e.g. vpn.aurora-net.org): " > /dev/stderr
  read -r READ_AURORANET_DOMAIN < /dev/tty
  if ! check_nb_domain "$READ_AURORANET_DOMAIN"; then
    read_nb_domain
    return
  fi

  if [[ "$READ_AURORANET_DOMAIN" != "use-ip" ]] && ! check_domain_resolves "$READ_AURORANET_DOMAIN"; then
    local confirm=""
    echo "" > /dev/stderr
    echo "Warning: '$READ_AURORANET_DOMAIN' does not resolve via DNS from this host." > /dev/stderr
    echo "TLS certificate issuance and client connections will fail until it does." > /dev/stderr
    echo -n "Continue anyway? [y/N]: " > /dev/stderr
    read -r confirm < /dev/tty
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      read_nb_domain
      return
    fi
  fi

  echo "$READ_AURORANET_DOMAIN"
  return 0
}

read_reverse_proxy_type() {
  echo "" > /dev/stderr
  echo "Which reverse proxy will you use?" > /dev/stderr
  echo "  [0] Traefik (recommended - automatic TLS, included in Docker Compose)" > /dev/stderr
  echo "  [1] Existing Traefik (labels for external Traefik instance)" > /dev/stderr
  echo "  [2] Nginx (generates config template)" > /dev/stderr
  echo "  [3] Nginx Proxy Manager (generates config + instructions)" > /dev/stderr
  echo "  [4] External Caddy (generates Caddyfile snippet)" > /dev/stderr
  echo "  [5] Other/Manual (displays setup documentation)" > /dev/stderr
  echo "" > /dev/stderr
  echo -n "Enter choice [0-5] (default: 0): " > /dev/stderr
  read -r CHOICE < /dev/tty

  if [[ -z "$CHOICE" ]]; then
    CHOICE="0"
  fi

  if [[ ! "$CHOICE" =~ ^[0-5]$ ]]; then
    echo "Invalid choice. Please enter a number between 0 and 5." > /dev/stderr
    read_reverse_proxy_type
    return
  fi

  echo "$CHOICE"
  return 0
}

read_traefik_network() {
  echo "" > /dev/stderr
  echo "If you have an existing Traefik instance, enter its external network name." > /dev/stderr
  echo -n "External network (leave empty to create 'auroranet' network): " > /dev/stderr
  read -r NETWORK < /dev/tty
  echo "$NETWORK"
  return 0
}

read_traefik_entrypoint() {
  echo "" > /dev/stderr
  echo "Enter the name of your Traefik HTTPS entrypoint." > /dev/stderr
  echo -n "HTTPS entrypoint name (default: websecure): " > /dev/stderr
  read -r ENTRYPOINT < /dev/tty
  if [[ -z "$ENTRYPOINT" ]]; then
    ENTRYPOINT="websecure"
  fi
  echo "$ENTRYPOINT"
  return 0
}

read_traefik_certresolver() {
  echo "" > /dev/stderr
  echo "Enter the name of your Traefik certificate resolver (for automatic TLS)." > /dev/stderr
  echo "Leave empty if you handle TLS termination elsewhere or use a wildcard cert." > /dev/stderr
  echo -n "Certificate resolver name (e.g., letsencrypt): " > /dev/stderr
  read -r RESOLVER < /dev/tty
  echo "$RESOLVER"
  return 0
}

read_port_binding_preference() {
  echo "" > /dev/stderr
  echo "Should container ports be bound to localhost only (127.0.0.1)?" > /dev/stderr
  echo "Choose 'yes' if your reverse proxy runs on the same host (more secure)." > /dev/stderr
  echo -n "Bind to localhost only? [Y/n]: " > /dev/stderr
  read -r CHOICE < /dev/tty

  if [[ "$CHOICE" =~ ^[Nn]$ ]]; then
    echo "false"
  else
    echo "true"
  fi
  return 0
}

read_proxy_docker_network() {
  local proxy_name="$1"
  echo "" > /dev/stderr
  echo "Is ${proxy_name} running in Docker?" > /dev/stderr
  echo "If yes, enter the Docker network ${proxy_name} is on (AuroraNet will join it)." > /dev/stderr
  echo -n "Docker network (leave empty if not in Docker): " > /dev/stderr
  read -r NETWORK < /dev/tty
  echo "$NETWORK"
  return 0
}

read_enable_proxy() {
  echo "" > /dev/stderr
  echo "Do you want to enable the AuroraNet Proxy service?" > /dev/stderr
  echo "The proxy allows you to selectively expose internal AuroraNet network resources" > /dev/stderr
  echo "to the internet. You control which resources are exposed through the dashboard." > /dev/stderr
  echo -n "Enable proxy? [y/N]: " > /dev/stderr
  read -r CHOICE < /dev/tty

  if [[ "$CHOICE" =~ ^[Yy]$ ]]; then
    echo "true"
  else
    echo "false"
  fi
  return 0
}

read_enable_crowdsec() {
  echo "" > /dev/stderr
  echo "Do you want to enable CrowdSec IP reputation blocking?" > /dev/stderr
  echo "CrowdSec checks client IPs against a community threat intelligence database" > /dev/stderr
  echo "and blocks known malicious sources before they reach your services." > /dev/stderr
  echo "A local CrowdSec LAPI container will be added to your deployment." > /dev/stderr
  echo -n "Enable CrowdSec? [y/N]: " > /dev/stderr
  read -r CHOICE < /dev/tty

  if [[ "$CHOICE" =~ ^[Yy]$ ]]; then
    echo "true"
  else
    echo "false"
  fi
  return 0
}

read_enable_crowdsec_appsec() {
  echo "" > /dev/stderr
  echo "Protect the dashboard with CrowdSec AppSec?" > /dev/stderr
  echo "AppSec inspects requests to the dashboard, /api, and /oauth2 and blocks" > /dev/stderr
  echo "common web attack patterns. Relay, gRPC, and proxied services are not" > /dev/stderr
  echo "inspected." > /dev/stderr
  echo "" > /dev/stderr
  echo "If CrowdSec is unreachable, those paths are blocked. Two different rule" > /dev/stderr
  echo "matches from your IP within a minute can lock you out of the dashboard" > /dev/stderr
  echo "for 4 hours. Recovery is over SSH." > /dev/stderr
  echo -n "Enable AppSec? [y/N]: " > /dev/stderr
  read -r CHOICE < /dev/tty

  if [[ "$CHOICE" =~ ^[Yy]$ ]]; then
    echo "true"
  else
    echo "false"
  fi
  return 0
}

# AppSec is enforced by the built-in Traefik on the dashboard paths. It has no
# engine of its own, so it cannot be selected without CrowdSec.
ensure_crowdsec_appsec_allowed() {
  if [[ "${AURORANET_ENABLE_CROWDSEC_APPSEC:-}" == "true" && "${ENABLE_CROWDSEC:-}" != "true" ]]; then
    echo "AURORANET_ENABLE_CROWDSEC_APPSEC=true requires AURORANET_ENABLE_CROWDSEC=true with the built-in Traefik reverse proxy and the AuroraNet Proxy." > /dev/stderr
    exit 1
  fi
  return 0
}

read_traefik_acme_email() {
  echo "" > /dev/stderr
  echo "Enter your email for Let's Encrypt certificate notifications." > /dev/stderr
  echo -n "Email address: " > /dev/stderr
  read -r EMAIL < /dev/tty
  if [[ -z "$EMAIL" ]]; then
    echo "Email is required for Let's Encrypt." > /dev/stderr
    read_traefik_acme_email
    return
  fi
  echo "$EMAIL"
  return 0
}

get_bind_address() {
  if [[ "$BIND_LOCALHOST_ONLY" == "true" ]]; then
    echo "127.0.0.1"
  else
    echo "0.0.0.0"
  fi
  return 0
}

get_upstream_host() {
  # Always return 127.0.0.1 for health checks and upstream targets
  # Cannot use 0.0.0.0 as a connection target
  echo "127.0.0.1"
  return 0
}

wait_management_proxy() {
  local proxy_container="${1:-traefik}"
  local use_docker_logs=false
  set +e

  if [[ "$proxy_container" == "detect-traefik" ]]; then
    proxy_container=$(docker ps --format "{{.ID}}\t{{.Image}}\t{{.Ports}}" \
    | awk -F'\t' '$2 ~ /traefik/ && $3 ~ /:(80|443)->/ {print $1; exit}')

    if [[ -z "$proxy_container" ]]; then
      echo "Warning: could not auto-detect Traefik container, log output will be skipped on timeout." > /dev/stderr
    else
      use_docker_logs=true
    fi
  fi

  echo -n "Waiting for AuroraNet server to become ready"
  counter=1
  while true; do
    # Check the embedded IdP endpoint through the reverse proxy
    if curl -sk -f -o /dev/null "$AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN/oauth2/.well-known/openid-configuration" 2>/dev/null; then
      break
    fi
    if [[ $counter -eq 60 ]]; then
      echo ""
      echo "Taking too long. Checking logs..."
      if [[ -n "$proxy_container" ]]; then
        if [[ "$use_docker_logs" == "true" ]]; then
          docker logs --tail=20 "$proxy_container"
        else
          $DOCKER_COMPOSE_COMMAND logs --tail=20 "$proxy_container"
        fi
      fi
      $DOCKER_COMPOSE_COMMAND logs --tail=20 auroranet-server
    fi
    echo -n " ."
    sleep 2
    counter=$((counter + 1))
  done
  echo " done"
  set -e
  return 0
}

wait_management_direct() {
  set +e
  local upstream_host=$(get_upstream_host)
  echo -n "Waiting for AuroraNet server to become ready"
  counter=1
  while true; do
    # Check the embedded IdP endpoint directly (no reverse proxy)
    if curl -sk -f -o /dev/null "http://${upstream_host}:${MANAGEMENT_HOST_PORT}/oauth2/.well-known/openid-configuration" 2>/dev/null; then
      break
    fi
    if [[ $counter -eq 60 ]]; then
      echo ""
      echo "Taking too long. Checking logs..."
      $DOCKER_COMPOSE_COMMAND logs --tail=20 auroranet-server
    fi
    echo -n " ."
    sleep 2
    counter=$((counter + 1))
  done
  echo " done"
  set -e
  return 0
}

############################################
# Initialization and Configuration
############################################

initialize_default_values() {
  AURORANET_PORT=80
  AURORANET_HTTP_PROTOCOL="http"
  AURORANET_RELAY_PROTO="rel"
  AURORANET_RELAY_AUTH_SECRET=$(openssl rand -base64 32 | sed "$SED_STRIP_PADDING")
  # Note: DataStoreEncryptionKey must keep base64 padding (=) for Go's base64.StdEncoding
  DATASTORE_ENCRYPTION_KEY=$(openssl rand -base64 32)
  SESSION_COOKIE_ENCRYPTION_KEY=$(openssl rand -base64 32)
  AURORANET_STUN_PORT=3478

  # Docker images
  DASHBOARD_IMAGE=${DASHBOARD_IMAGE:-"ghcr.io/haxygame/auroranet-dashboard:latest"}
  # Combined server replaces separate signal, relay, and management containers
  AURORANET_SERVER_IMAGE=${AURORANET_SERVER_IMAGE:-"ghcr.io/haxygame/auroranet-server:latest"}
  AURORANET_PROXY_IMAGE=${AURORANET_PROXY_IMAGE:-"ghcr.io/haxygame/auroranet-proxy:latest"}
  TRAEFIK_IMAGE=${TRAEFIK_IMAGE:-"traefik:v3.7.18"}
  CROWDSEC_IMAGE=${CROWDSEC_IMAGE:-"crowdsecurity/crowdsec:v1.8.1"}
  # Reverse proxy configuration
  REVERSE_PROXY_TYPE="0"
  TRAEFIK_EXTERNAL_NETWORK=""
  TRAEFIK_ENTRYPOINT="websecure"
  TRAEFIK_CERTRESOLVER=""
  TRAEFIK_ACME_EMAIL=""
  DASHBOARD_HOST_PORT="8080"
  MANAGEMENT_HOST_PORT="8081"  # Combined server port (management + signal + relay)
  BIND_LOCALHOST_ONLY="true"
  EXTERNAL_PROXY_NETWORK=""
  TRUSTED_PEERS=""             # Address the reverse proxy connects to management from


  # Traefik static IP within the internal bridge network
  TRAEFIK_IP="172.30.0.10"

  # AuroraNet Proxy configuration
  ENABLE_PROXY="false"
  PROXY_TOKEN=""

  # CrowdSec configuration
  ENABLE_CROWDSEC="false"
  ENABLE_CROWDSEC_APPSEC="false"
  CROWDSEC_BOUNCER_KEY=""
  return 0
}

configure_domain() {
  # Domain is validated (not a free-form value), so it keeps its own guard
  # rather than going through resolve(): a valid AURORANET_DOMAIN is used as-is,
  # otherwise we prompt, or abort when there is no terminal to prompt on.
  local prompted="false"
  if ! check_nb_domain "$AURORANET_DOMAIN"; then
    if ! tty_available; then
      if [[ -n "$AURORANET_DOMAIN" ]]; then
        echo "AURORANET_DOMAIN='$AURORANET_DOMAIN' cannot be used for a non-interactive install." > /dev/stderr
      else
        echo "AURORANET_DOMAIN is required for a non-interactive install." > /dev/stderr
      fi
      exit 1
    fi
    AURORANET_DOMAIN=$(read_nb_domain)
    prompted="true"
  fi

  if [[ "$prompted" == "false" && "$AURORANET_DOMAIN" != "use-ip" ]] && ! check_domain_resolves "$AURORANET_DOMAIN"; then
    echo "Warning: '$AURORANET_DOMAIN' does not resolve via DNS from this host." > /dev/stderr
    echo "TLS certificate issuance and client connections will fail until it does." > /dev/stderr
  fi

  if [[ "$AURORANET_DOMAIN" == "use-ip" ]]; then
    AURORANET_DOMAIN=$(get_main_ip_address)
    BASE_DOMAIN=$AURORANET_DOMAIN
  else
    AURORANET_PORT=443
    AURORANET_HTTP_PROTOCOL="https"
    AURORANET_RELAY_PROTO="rels"
    BASE_DOMAIN=$(echo $AURORANET_DOMAIN | sed -E 's/^[^.]+\.//')
  fi
  return 0
}

apply_agent_network_preset() {
  # Agent-network turnkey install: built-in Traefik + AuroraNet Proxy with
  # NB_PROXY_PRIVATE=true, dashboard locked to agent-network-only mode.
  # Bypasses every reverse-proxy / proxy / CrowdSec prompt. The only
  # inputs we still need from the operator are the domain (handled by
  # configure_domain via AURORANET_DOMAIN env var or interactive prompt)
  # and the ACME email — both honor env vars first and fall back to a
  # prompt only when unset. CrowdSec is intentionally off.
  REVERSE_PROXY_TYPE="0"
  ENABLE_PROXY="true"
  ENABLE_CROWDSEC="false"
  TRUSTED_PEERS="${AURORANET_TRUSTED_PEERS:-$TRAEFIK_IP/32}"

  TRAEFIK_ACME_EMAIL=$(resolve AURORANET_EMAIL required read_traefik_acme_email)

  echo "" > /dev/stderr
  echo "Agent-network preset enabled (AURORANET_AGENT_NETWORK=true):" > /dev/stderr
  echo "  - reverse proxy: built-in Traefik" > /dev/stderr
  echo "  - AuroraNet Proxy: enabled with NB_PROXY_PRIVATE=true" > /dev/stderr
  echo "  - server image: ${AURORANET_SERVER_IMAGE}" > /dev/stderr
  echo "  - proxy image: ${AURORANET_PROXY_IMAGE}" > /dev/stderr
  echo "  - dashboard: AURORANET_AGENT_NETWORK_ONLY=true" > /dev/stderr
  echo "  - CrowdSec: disabled" > /dev/stderr
  echo "  - Let's Encrypt email: ${TRAEFIK_ACME_EMAIL}" > /dev/stderr
  echo "" > /dev/stderr
}

configure_reverse_proxy() {
  # AURORANET_EMAIL is the documented name; keep accepting the old name.
  AURORANET_EMAIL="${AURORANET_EMAIL:-${AURORANET_LETSENCRYPT_EMAIL:-}}"
  validate_boolean_env AURORANET_ENABLE_CROWDSEC_APPSEC

  # Short-circuit: agent-network preset locks every reverse-proxy /
  # proxy / CrowdSec choice and bypasses the interactive prompts.
  if [[ "${AURORANET_AGENT_NETWORK}" == "true" ]]; then
    apply_agent_network_preset
    ensure_crowdsec_appsec_allowed
    return 0
  fi

  # Reverse proxy type (env AURORANET_REVERSE_PROXY_TYPE, else prompt, else 0)
  REVERSE_PROXY_TYPE=$(resolve AURORANET_REVERSE_PROXY_TYPE 0 read_reverse_proxy_type)

  # Handle built-in Traefik prompts (option 0)
  if [[ "$REVERSE_PROXY_TYPE" == "0" ]]; then
    TRAEFIK_ACME_EMAIL=$(resolve AURORANET_EMAIL required read_traefik_acme_email)
    ENABLE_PROXY=$(resolve AURORANET_ENABLE_PROXY false read_enable_proxy)
    if [[ "$ENABLE_PROXY" == "true" ]]; then
      ENABLE_CROWDSEC=$(resolve AURORANET_ENABLE_CROWDSEC false read_enable_crowdsec)
      if [[ "$ENABLE_CROWDSEC" == "true" ]]; then
        ENABLE_CROWDSEC_APPSEC=$(resolve AURORANET_ENABLE_CROWDSEC_APPSEC false read_enable_crowdsec_appsec)
      fi
    fi
  fi

  # Handle external Traefik-specific prompts (option 1)
  if [[ "$REVERSE_PROXY_TYPE" == "1" ]]; then
    TRAEFIK_EXTERNAL_NETWORK=$(resolve AURORANET_TRAEFIK_EXTERNAL_NETWORK "" read_traefik_network)
    TRAEFIK_ENTRYPOINT=$(resolve AURORANET_TRAEFIK_ENTRYPOINT websecure read_traefik_entrypoint)
    TRAEFIK_CERTRESOLVER=$(resolve AURORANET_TRAEFIK_CERTRESOLVER "" read_traefik_certresolver)
  fi

  # Handle port binding for external proxy options (2-5)
  if [[ "$REVERSE_PROXY_TYPE" -ge 2 ]]; then
    BIND_LOCALHOST_ONLY=$(resolve AURORANET_BIND_LOCALHOST_ONLY true read_port_binding_preference)
  fi

  # Handle Docker network prompts for external proxies (options 2-4)
  case "$REVERSE_PROXY_TYPE" in
    2) EXTERNAL_PROXY_NETWORK=$(resolve AURORANET_EXTERNAL_PROXY_NETWORK "" read_proxy_docker_network "Nginx") ;;
    3) EXTERNAL_PROXY_NETWORK=$(resolve AURORANET_EXTERNAL_PROXY_NETWORK "" read_proxy_docker_network "Nginx Proxy Manager") ;;
    4) EXTERNAL_PROXY_NETWORK=$(resolve AURORANET_EXTERNAL_PROXY_NETWORK "" read_proxy_docker_network "Caddy") ;;
    *) ;; # No network prompt for other options
  esac

  # Only the bundled Traefik has an address we know at render time. External proxies
  # must supply the address their proxy reaches management from.
  if [[ "$REVERSE_PROXY_TYPE" == "0" ]]; then
    TRUSTED_PEERS="${AURORANET_TRUSTED_PEERS:-$TRAEFIK_IP/32}"
  else
    TRUSTED_PEERS="${AURORANET_TRUSTED_PEERS:-}"
    if [[ -z "$TRUSTED_PEERS" ]]; then
      echo "" > /dev/stderr
      echo "Warning: reverseProxy.trustedPeers is unset, so all IPv4 and IPv6 sources" > /dev/stderr
      echo "are trusted to provide forwarded client-IP headers. Set AURORANET_TRUSTED_PEERS" > /dev/stderr
      echo "to your proxy's address (e.g. 172.20.0.5/32) and re-run." > /dev/stderr
      echo "" > /dev/stderr
    fi
  fi
  ensure_crowdsec_appsec_allowed
  return 0
}

check_existing_installation() {
  if [[ -f config.yaml ]]; then
    echo "Generated files already exist, if you want to reinitialize the environment, please remove them first."
    echo "You can use the following commands:"
    echo "  $DOCKER_COMPOSE_COMMAND down --volumes # to remove all containers and volumes"
    echo "  if [ -f .env ]; then sed -i '/^CROWDSEC_DASHBOARD_BOUNCER_KEY=/d' .env; fi"
    echo "  rm -f docker-compose.yml dashboard.env config.yaml proxy.env traefik-dynamic.yaml nginx-auroranet.conf caddyfile-auroranet.txt npm-advanced-config.txt && rm -rf crowdsec/"
    echo "Be aware that this will remove all data from the database, and you will have to reconfigure the dashboard."
    exit 1
  fi
  return 0
}

generate_configuration_files() {
  echo Rendering initial files...

  # Render docker-compose and proxy config based on selection
  case "$REVERSE_PROXY_TYPE" in
    0)
      check_traefik_image || return 1
      render_docker_compose_traefik_builtin > docker-compose.yml
      if [[ "$ENABLE_PROXY" == "true" ]]; then
        # Create placeholder proxy.env so docker-compose can validate
        # This will be overwritten with the actual token after auroranet-server starts
        echo "# Placeholder - will be updated with token after auroranet-server starts" > proxy.env
        echo "NB_PROXY_TOKEN=placeholder" >> proxy.env
        # TCP ServersTransport for PROXY protocol v2 to the proxy backend
        render_traefik_dynamic > traefik-dynamic.yaml
        if [[ "$ENABLE_CROWDSEC" == "true" ]]; then
          mkdir -p crowdsec
          if [[ "$ENABLE_CROWDSEC_APPSEC" == "true" ]]; then
            write_crowdsec_appsec_files
          fi
        fi
      fi
      ;;
    1)
      render_docker_compose_traefik > docker-compose.yml
      ;;
    2)
      render_docker_compose_exposed_ports > docker-compose.yml
      render_nginx_conf > nginx-auroranet.conf
      ;;
    3)
      render_docker_compose_exposed_ports > docker-compose.yml
      render_npm_advanced_config > npm-advanced-config.txt
      ;;
    4)
      render_docker_compose_exposed_ports > docker-compose.yml
      render_external_caddyfile > caddyfile-auroranet.txt
      ;;
    5)
      render_docker_compose_exposed_ports > docker-compose.yml
      ;;
    *)
      echo "Invalid reverse proxy type: $REVERSE_PROXY_TYPE" > /dev/stderr
      exit 1
      ;;
  esac

  # Common files for all configurations
  render_dashboard_env > dashboard.env
  install -m 600 /dev/null config.yaml
  render_combined_yaml >> config.yaml
  return 0
}

start_services_and_show_instructions() {
  # For built-in Traefik, start containers immediately
  # For NPM, start containers first (NPM needs services running to create proxy)
  # For other external proxies, show instructions first and wait for user confirmation
  if [[ "$REVERSE_PROXY_TYPE" == "0" ]]; then
    # Built-in Traefik - two-phase startup if proxy is enabled
    echo -e "$MSG_STARTING_SERVICES"

    if [[ "$ENABLE_PROXY" == "true" ]]; then
      # Phase 1: Start core services (without proxy)
      local core_services="traefik dashboard auroranet-server"
      if [[ "$ENABLE_CROWDSEC" == "true" ]]; then
        core_services="$core_services crowdsec"
      fi
      echo "Starting core services..."
      $DOCKER_COMPOSE_COMMAND up -d $core_services

      sleep 3
      wait_management_proxy traefik

      # Phase 2: Create proxy token and start proxy
      echo ""
      echo "Creating proxy access token..."
      # Use docker exec with bash to run the token command directly
      PROXY_TOKEN=$($DOCKER_COMPOSE_COMMAND exec -T auroranet-server \
        /go/bin/auroranet-server admin token create --name "default-proxy" --config /etc/auroranet/config.yaml 2>/dev/null | grep "^Token:" | awk '{print $2}')

      if [[ -z "$PROXY_TOKEN" ]]; then
        echo "ERROR: Failed to create proxy token. Check auroranet-server logs." > /dev/stderr
        $DOCKER_COMPOSE_COMMAND logs --tail=20 auroranet-server
        exit 1
      fi

      echo "Proxy token created successfully."

      if [[ "$ENABLE_CROWDSEC" == "true" ]]; then
        echo "Registering CrowdSec bouncer..."
        local cs_retries=0
        while ! $DOCKER_COMPOSE_COMMAND exec -T crowdsec cscli lapi status >/dev/null 2>&1; do
          cs_retries=$((cs_retries + 1))
          if [[ $cs_retries -ge 30 ]]; then
            echo "WARNING: CrowdSec did not become ready. Skipping CrowdSec setup." > /dev/stderr
            echo "You can register a bouncer manually later with:" > /dev/stderr
            echo "  docker exec auroranet-crowdsec cscli bouncers add auroranet-proxy -o raw" > /dev/stderr
            ENABLE_CROWDSEC="false"
            break
          fi
          sleep 2
        done

        if [[ "$ENABLE_CROWDSEC" == "true" ]]; then
          CROWDSEC_BOUNCER_KEY=$($DOCKER_COMPOSE_COMMAND exec -T crowdsec \
            cscli bouncers add auroranet-proxy -o raw 2>/dev/null)
          if [[ -z "$CROWDSEC_BOUNCER_KEY" ]]; then
            echo "WARNING: Failed to create CrowdSec bouncer key. Skipping CrowdSec setup." > /dev/stderr
            ENABLE_CROWDSEC="false"
          else
            echo "CrowdSec bouncer registered."
          fi
        fi
      fi

      render_proxy_env > proxy.env

      # Start proxy service
      echo "Starting proxy service..."
      $DOCKER_COMPOSE_COMMAND up -d proxy
    else
      # No proxy - start all services at once
      $DOCKER_COMPOSE_COMMAND up -d

      sleep 3
      wait_management_proxy traefik
    fi

    echo -e "$MSG_DONE"
    print_post_setup_instructions
  elif [[ "$REVERSE_PROXY_TYPE" == "1" ]]; then
    # External Traefik - start containers, then show instructions
    # Traefik discovers services via Docker labels, so containers must be running
    echo -e "$MSG_STARTING_SERVICES"
    $DOCKER_COMPOSE_COMMAND up -d

    sleep 3
    wait_management_proxy detect-traefik

    echo -e "$MSG_DONE"
    print_post_setup_instructions
    echo ""
    echo "AuroraNet containers are running. Once Traefik is connected, access the dashboard at:"
    echo "  $AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN"
  elif [[ "$REVERSE_PROXY_TYPE" == "3" ]]; then
    # NPM - start containers first, then show instructions
    # NPM requires backend services to be running before creating proxy hosts
    echo -e "$MSG_STARTING_SERVICES"
    $DOCKER_COMPOSE_COMMAND up -d

    sleep 3
    wait_management_direct

    echo -e "$MSG_DONE"
    print_post_setup_instructions
    echo ""
    echo "AuroraNet containers are running. Configure NPM as shown above, then access:"
    echo "  $AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN"
  else
    # External proxies (nginx, external Caddy, other) - need manual config first
    print_post_setup_instructions

    echo ""
    if tty_available; then
      echo -n "Press Enter when your reverse proxy is configured (or Ctrl+C to exit)... "
      read -r < /dev/tty
    else
      echo "Non-interactive mode: starting AuroraNet containers now. Finish configuring"
      echo "your reverse proxy using the instructions above so it can reach them."
    fi

    echo -e "$MSG_STARTING_SERVICES"
    $DOCKER_COMPOSE_COMMAND up -d

    sleep 3
    wait_management_direct

    echo -e "$MSG_DONE"
    echo "AuroraNet is now running. Access the dashboard at:"
    echo "  $AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN"
  fi
  return 0
}

init_environment() {
  # Check if docker compose is installed using check_docker_compose function
  DOCKER_COMPOSE_COMMAND=$(check_docker_compose)
  check_docker_sock_perms

  initialize_default_values
  configure_domain
  configure_reverse_proxy

  check_jq

  check_existing_installation
  generate_configuration_files
  start_services_and_show_instructions
  return 0
}

############################################
# Configuration File Renderers
############################################

# Port 7422 stays closed unless this file exists before the container is
# created. Traefik waits on a health check that opens that port.
write_crowdsec_appsec_files() {
  mkdir -p crowdsec/acquis.d
  cat > crowdsec/acquis.d/appsec.yaml <<'EOF'
appsec_configs:
  - crowdsecurity/appsec-default
labels:
  type: appsec
listen_addr: 0.0.0.0:7422
source: appsec
EOF
  if [[ -f .env ]] && grep -q '^CROWDSEC_DASHBOARD_BOUNCER_KEY=.' .env; then
    chmod 600 .env
    return 0
  fi
  local key
  key=$(openssl rand -hex 32) || {
    echo "Could not generate the CrowdSec dashboard bouncer key." > /dev/stderr
    exit 1
  }
  if [[ -z "$key" ]]; then
    echo "Could not generate the CrowdSec dashboard bouncer key." > /dev/stderr
    exit 1
  fi
  if [[ ! -f .env ]]; then
    install -m 600 /dev/null .env
  fi
  printf 'CROWDSEC_DASHBOARD_BOUNCER_KEY=%s\n' "$key" >> .env
  chmod 600 .env
  return 0
}

# The dashboard bouncer key stays in .env. Compose interpolates it.
render_crowdsec_appsec_service() {
  cat <<EOF
  crowdsec:
    image: $CROWDSEC_IMAGE
    container_name: auroranet-crowdsec
    restart: unless-stopped
    networks: [auroranet]
    environment:
      COLLECTIONS: "crowdsecurity/linux crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules"
      BOUNCER_KEY_auroranet_dashboard: "\${CROWDSEC_DASHBOARD_BOUNCER_KEY}"
    volumes:
      - ./crowdsec:/etc/crowdsec
      - crowdsec_db:/var/lib/crowdsec/data
    healthcheck:
      test: ["CMD-SHELL", "cscli lapi status >/dev/null 2>&1 && bash -c '</dev/tcp/127.0.0.1/7422'"]
      interval: 10s
      timeout: 5s
      retries: 15
      start_period: 30s
    labels:
      - traefik.enable=false
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"
EOF
}

render_docker_compose_traefik_builtin() {
  # Generate proxy service section and Traefik dynamic config if enabled
  local proxy_service=""
  local proxy_volumes=""
  local crowdsec_service=""
  local crowdsec_volumes=""
  local traefik_file_provider=""
  local traefik_dynamic_volume=""
  local traefik_depends=""
  local traefik_plugin=""
  local traefik_appsec_labels=""
  local dashboard_appsec_middleware=""
  local dashboard_api_router=""
  local backend_paths='PathPrefix(`/relay`) || PathPrefix(`/ws-proxy/`)'
  # API and OAuth2 must not fall back to an uninspected router when AppSec fails.
  if [[ "$ENABLE_CROWDSEC_APPSEC" != "true" ]]; then
    backend_paths+=' || PathPrefix(`/api`) || PathPrefix(`/oauth2`)'
  fi
  if [[ "$ENABLE_PROXY" == "true" ]]; then
    traefik_file_provider='      - "--providers.file.filename=/etc/traefik/dynamic.yaml"'
    traefik_dynamic_volume="      - ./traefik-dynamic.yaml:/etc/traefik/dynamic.yaml:ro"

    local proxy_depends="
      auroranet-server:
        condition: service_started"
    if [[ "$ENABLE_CROWDSEC" == "true" ]]; then
      proxy_depends="
      auroranet-server:
        condition: service_started
      crowdsec:
        condition: service_healthy"
    fi

    proxy_service="
  # AuroraNet Proxy - exposes internal resources to the internet
  proxy:
    image: $AURORANET_PROXY_IMAGE
    container_name: auroranet-proxy
    ports:
    - 51820:51820/udp
    restart: unless-stopped
    networks: [auroranet]
    depends_on:${proxy_depends}
    env_file:
      - ./proxy.env
    volumes:
      - auroranet_proxy_certs:/certs
    labels:
      # TCP passthrough for any unmatched domain (proxy handles its own TLS)
      - traefik.enable=true
      - traefik.tcp.routers.proxy-passthrough.entrypoints=websecure
      - traefik.tcp.routers.proxy-passthrough.rule=HostSNI(\`*\`)
      - traefik.tcp.routers.proxy-passthrough.tls.passthrough=true
      - traefik.tcp.routers.proxy-passthrough.service=proxy-tls
      - traefik.tcp.routers.proxy-passthrough.priority=1
      - traefik.tcp.services.proxy-tls.loadbalancer.server.port=8443
      - traefik.tcp.services.proxy-tls.loadbalancer.serverstransport=pp-v2@file
    logging:
      driver: \"json-file\"
      options:
        max-size: \"500m\"
        max-file: \"2\"
"
    proxy_volumes="
  auroranet_proxy_certs:"

    if [[ "$ENABLE_CROWDSEC" == "true" ]]; then
      if [[ "$ENABLE_CROWDSEC_APPSEC" == "true" ]]; then
        crowdsec_service=$(render_crowdsec_appsec_service)
        crowdsec_service+=$'\n'
      else
        crowdsec_service="
  crowdsec:
    image: $CROWDSEC_IMAGE
    container_name: auroranet-crowdsec
    restart: unless-stopped
    networks: [auroranet]
    environment:
      COLLECTIONS: crowdsecurity/linux
    volumes:
      - ./crowdsec:/etc/crowdsec
      - crowdsec_db:/var/lib/crowdsec/data
    healthcheck:
      test: ["CMD", "cscli", "lapi", "status"]
      interval: 10s
      timeout: 5s
      retries: 15
    labels:
      - traefik.enable=false
    logging:
      driver: \"json-file\"
      options:
        max-size: \"500m\"
        max-file: \"2\"
"
      fi
      crowdsec_volumes="
  crowdsec_db:"
    fi
  fi

  # v1.7.1 is the bouncer plugin release validated with CrowdSec 1.8.1 and
  # Traefik 3.7.14. The middleware is declared on Traefik so a dashboard
  # restart does not drop it and fail open.
  if [[ "$ENABLE_CROWDSEC_APPSEC" == "true" ]]; then
    traefik_depends=$(cat <<'EOF'
    depends_on:
      crowdsec:
        condition: service_healthy
EOF
)
    traefik_depends+=$'\n'
    traefik_plugin=$(cat <<'EOF'
      - "--experimental.plugins.bouncer.modulename=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
      - "--experimental.plugins.bouncer.version=v1.7.1"
EOF
)
    traefik_plugin+=$'\n'
    traefik_appsec_labels=$(cat <<'EOF'
    labels:
      - traefik.enable=true
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.enabled=true
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.crowdsecMode=stream
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.crowdsecLapiScheme=http
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.crowdsecLapiHost=crowdsec:8080
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.crowdsecLapiKey=${CROWDSEC_DASHBOARD_BOUNCER_KEY}
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.crowdsecAppsecEnabled=true
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.crowdsecAppsecHost=crowdsec:7422
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.crowdsecAppsecFailureBlock=true
      - traefik.http.middlewares.auroranet-dashboard-crowdsec.plugin.bouncer.crowdsecAppsecUnreachableBlock=true
EOF
)
    traefik_appsec_labels+=$'\n'
    dashboard_appsec_middleware=$(cat <<'EOF'
      - traefik.http.routers.auroranet-dashboard.middlewares=auroranet-dashboard-crowdsec@docker
EOF
)
    dashboard_appsec_middleware+=$'\n'
    dashboard_api_router=$(cat <<EOF
      - traefik.http.routers.auroranet-dashboard-api.rule=Host(\`$AURORANET_DOMAIN\`) && (PathPrefix(\`/api\`) || PathPrefix(\`/oauth2\`))
      - traefik.http.routers.auroranet-dashboard-api.entrypoints=websecure
      - traefik.http.routers.auroranet-dashboard-api.tls=true
      - traefik.http.routers.auroranet-dashboard-api.tls.certresolver=letsencrypt
      - traefik.http.routers.auroranet-dashboard-api.service=auroranet-server
      - traefik.http.routers.auroranet-dashboard-api.middlewares=auroranet-dashboard-crowdsec@docker
      - traefik.http.routers.auroranet-dashboard-api.priority=110
EOF
)
    dashboard_api_router+=$'\n'
  fi

  cat <<EOF
services:
  # Traefik reverse proxy (automatic TLS via Let's Encrypt)
  traefik:
    image: $TRAEFIK_IMAGE
    container_name: auroranet-traefik
    restart: unless-stopped
    networks:
      auroranet:
        ipv4_address: $TRAEFIK_IP
${traefik_depends}    command:
      # Logging
      - "--log.level=INFO"
      - "--accesslog=true"
      # Docker provider
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=\${COMPOSE_PROJECT_NAME:-}_auroranet"
      # Entrypoints
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.websecure.allowACMEByPass=true"
      - "--entrypoints.web.http.aliasHeadersStrategy=delete"
      - "--entrypoints.websecure.http.aliasHeadersStrategy=delete"
${traefik_plugin}      # Disable timeouts for long-lived gRPC streams
      - "--entrypoints.websecure.transport.respondingTimeouts.readTimeout=0"
      - "--entrypoints.websecure.transport.respondingTimeouts.writeTimeout=0"
      - "--entrypoints.websecure.transport.respondingTimeouts.idleTimeout=0"
      # HTTP to HTTPS redirect
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      # Let's Encrypt ACME
      - "--certificatesresolvers.letsencrypt.acme.email=$TRAEFIK_ACME_EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      # gRPC transport settings
      - "--serverstransport.forwardingtimeouts.responseheadertimeout=0s"
      - "--serverstransport.forwardingtimeouts.idleconntimeout=0s"
$traefik_file_provider
    ports:
      - '443:443'
      - '80:80'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - auroranet_traefik_letsencrypt:/letsencrypt
$traefik_dynamic_volume
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"
${traefik_appsec_labels}
  # UI dashboard
  dashboard:
    image: $DASHBOARD_IMAGE
    container_name: auroranet-dashboard
    restart: unless-stopped
    networks: [auroranet]
    env_file:
      - ./dashboard.env
    labels:
      - traefik.enable=true
      - traefik.http.routers.auroranet-dashboard.rule=Host(\`$AURORANET_DOMAIN\`)
      - traefik.http.routers.auroranet-dashboard.entrypoints=websecure
      - traefik.http.routers.auroranet-dashboard.tls=true
      - traefik.http.routers.auroranet-dashboard.tls.certresolver=letsencrypt
      - traefik.http.routers.auroranet-dashboard.service=dashboard
${dashboard_appsec_middleware}      - traefik.http.routers.auroranet-dashboard.priority=1
      - traefik.http.services.dashboard.loadbalancer.server.port=80
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Combined server (Management + Signal + Relay + STUN)
  auroranet-server:
    image: $AURORANET_SERVER_IMAGE
    container_name: auroranet-server
    restart: unless-stopped
    networks: [auroranet]
    ports:
      - '$AURORANET_STUN_PORT:$AURORANET_STUN_PORT/udp'
    volumes:
      - auroranet_data:/var/lib/auroranet
      - ./config.yaml:/etc/auroranet/config.yaml
    command: ["--config", "/etc/auroranet/config.yaml"]
    labels:
      - traefik.enable=true
      # gRPC router (needs h2c backend for HTTP/2 cleartext)
      - traefik.http.routers.auroranet-grpc.rule=Host(\`$AURORANET_DOMAIN\`) && (PathPrefix(\`/signalexchange.SignalExchange/\`) || PathPrefix(\`/management.ManagementService/\`) || PathPrefix(\`/management.ProxyService/\`))
      - traefik.http.routers.auroranet-grpc.entrypoints=websecure
      - traefik.http.routers.auroranet-grpc.tls=true
      - traefik.http.routers.auroranet-grpc.tls.certresolver=letsencrypt
      - traefik.http.routers.auroranet-grpc.service=auroranet-server-h2c
      - traefik.http.routers.auroranet-grpc.priority=100
      # HTTP backend router
      - traefik.http.routers.auroranet-backend.rule=Host(\`$AURORANET_DOMAIN\`) && ($backend_paths)
      - traefik.http.routers.auroranet-backend.entrypoints=websecure
      - traefik.http.routers.auroranet-backend.tls=true
      - traefik.http.routers.auroranet-backend.tls.certresolver=letsencrypt
      - traefik.http.routers.auroranet-backend.service=auroranet-server
      - traefik.http.routers.auroranet-backend.priority=100
${dashboard_api_router}      # Services
      - traefik.http.services.auroranet-server.loadbalancer.server.port=80
      - traefik.http.services.auroranet-server-h2c.loadbalancer.server.port=80
      - traefik.http.services.auroranet-server-h2c.loadbalancer.server.scheme=h2c
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"
${proxy_service}${crowdsec_service}
volumes:
  auroranet_data:
  auroranet_traefik_letsencrypt:${proxy_volumes}${crowdsec_volumes}

networks:
  auroranet:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24
          gateway: 172.30.0.1
EOF
  return 0
}

render_combined_yaml() {
  cat <<EOF
# Combined AuroraNet Server Configuration (Simplified)
# Generated by getting-started.sh

server:
  listenAddress: ":80"
  exposedAddress: "$AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN:$AURORANET_PORT"
  stunPorts:
    - $AURORANET_STUN_PORT
  metricsPort: 9090
  healthcheckAddress: ":9000"
  logLevel: "info"
  logFile: "console"

  authSecret: "$AURORANET_RELAY_AUTH_SECRET"
  dataDir: "/var/lib/auroranet"

  auth:
    issuer: "$AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN/oauth2"
    signKeyRefreshEnabled: true
    sessionCookieEncryptionKey: "$SESSION_COOKIE_ENCRYPTION_KEY"
    dashboardRedirectURIs:
      - "$AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN/nb-auth"
      - "$AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN/nb-silent-auth"
    cliRedirectURIs:
      - "http://localhost:53000/"

  reverseProxy:
    trustedHTTPProxies:
      - "$TRAEFIK_IP/32"
$(render_trusted_peers)

  store:
    engine: "sqlite"
    encryptionKey: "$DATASTORE_ENCRYPTION_KEY"
EOF
  return 0
}

render_trusted_peers() {
  if [[ -n "$TRUSTED_PEERS" ]]; then
    printf '    trustedPeers:\n      - "%s"' "$TRUSTED_PEERS"
  fi
}

render_dashboard_env() {
  cat <<EOF
# Endpoints
AURORANET_MGMT_API_ENDPOINT=$AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN
AURORANET_MGMT_GRPC_API_ENDPOINT=$AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN
# OIDC - using embedded IdP
AUTH_AUDIENCE=auroranet-dashboard
AUTH_CLIENT_ID=auroranet-dashboard
AUTH_CLIENT_SECRET=
AUTH_AUTHORITY=$AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN/oauth2
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email groups
AUTH_REDIRECT_URI=/nb-auth
AUTH_SILENT_REDIRECT_URI=/nb-silent-auth
# SSL
NGINX_SSL_PORT=443
# Letsencrypt
LETSENCRYPT_DOMAIN=none
EOF

  if [[ "${AURORANET_AGENT_NETWORK}" == "true" ]]; then
    cat <<EOF
# Agent-network preset: dashboard hides the standard AuroraNet surfaces
# and exposes only the AI Observability + agent-network configuration
# pages. Paired with NB_PROXY_PRIVATE=true on the proxy side.
AURORANET_AGENT_NETWORK_ONLY=true
EOF
  fi
  return 0
}

render_traefik_dynamic() {
  cat <<'EOF'
tcp:
  serversTransports:
    pp-v2:
      proxyProtocol:
        version: 2
EOF
  return 0
}

render_proxy_env() {
  cat <<EOF
# AuroraNet Proxy Configuration
NB_PROXY_DEBUG_LOGS=false
# Use internal Docker network to connect to management (avoids hairpin NAT issues)
NB_PROXY_MANAGEMENT_ADDRESS=http://auroranet-server:80
# Allow insecure gRPC connection to management (required for internal Docker network)
NB_PROXY_ALLOW_INSECURE=true
# Public URL where this proxy is reachable (used for cluster registration)
NB_PROXY_DOMAIN=$AURORANET_DOMAIN
NB_PROXY_ADDRESS=:8443
NB_PROXY_TOKEN=$PROXY_TOKEN
NB_PROXY_CERTIFICATE_DIRECTORY=/certs
NB_PROXY_ACME_CERTIFICATES=true
NB_PROXY_ACME_CHALLENGE_TYPE=tls-alpn-01
NB_PROXY_FORWARDED_PROTO=https
# Enable PROXY protocol to preserve client IPs through L4 proxies (Traefik TCP passthrough)
NB_PROXY_PROXY_PROTOCOL=true
# Trust Traefik's IP for PROXY protocol headers
NB_PROXY_TRUSTED_PROXIES=$TRAEFIK_IP
EOF

  if [[ "${AURORANET_AGENT_NETWORK}" == "true" ]]; then
    cat <<EOF
# Agent-network preset: turn the proxy into the private reverse-proxy
# ingress for agent-network synth services. Disables the public-facing
# surface so the proxy serves only synth-generated routes (the
# llm_router-driven LLM endpoints) and the per-account inbound
# listeners on the embedded netstack.
NB_PROXY_PRIVATE=true
EOF
  fi

  if [[ "$ENABLE_CROWDSEC" == "true" && -n "$CROWDSEC_BOUNCER_KEY" ]]; then
    cat <<EOF
NB_PROXY_CROWDSEC_API_URL=http://crowdsec:8080
NB_PROXY_CROWDSEC_API_KEY=$CROWDSEC_BOUNCER_KEY
EOF
  fi

  return 0
}

render_docker_compose_traefik() {
  local network_name="${TRAEFIK_EXTERNAL_NETWORK:-auroranet}"
  local network_config=""
  if [[ -n "$TRAEFIK_EXTERNAL_NETWORK" ]]; then
    network_config="    external: true"
  fi

  # Build TLS labels - certresolver is optional
  local tls_labels=""
  if [[ -n "$TRAEFIK_CERTRESOLVER" ]]; then
    tls_labels="tls.certresolver=${TRAEFIK_CERTRESOLVER}"
  fi

  cat <<EOF
services:
  # UI dashboard
  dashboard:
    image: $DASHBOARD_IMAGE
    container_name: auroranet-dashboard
    restart: unless-stopped
    networks: [$network_name]
    env_file:
      - ./dashboard.env
    labels:
      - traefik.enable=true
      - traefik.http.routers.auroranet-dashboard.rule=Host(\`$AURORANET_DOMAIN\`)
      - traefik.http.routers.auroranet-dashboard.entrypoints=$TRAEFIK_ENTRYPOINT
      - traefik.http.routers.auroranet-dashboard.tls=true
$(if [[ -n "$tls_labels" ]]; then echo "      - traefik.http.routers.auroranet-dashboard.${tls_labels}"; fi)
      - traefik.http.routers.auroranet-dashboard.priority=1
      - traefik.http.services.auroranet-dashboard.loadbalancer.server.port=80
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Combined server (Management + Signal + Relay + STUN)
  auroranet-server:
    image: $AURORANET_SERVER_IMAGE
    container_name: auroranet-server
    restart: unless-stopped
    networks: [$network_name]
    ports:
      - '$AURORANET_STUN_PORT:$AURORANET_STUN_PORT/udp'
    volumes:
      - auroranet_data:/var/lib/auroranet
      - ./config.yaml:/etc/auroranet/config.yaml
    command: ["--config", "/etc/auroranet/config.yaml"]
    labels:
      - traefik.enable=true
      # gRPC router (needs h2c backend for HTTP/2 cleartext)
      - traefik.http.routers.auroranet-grpc.rule=Host(\`$AURORANET_DOMAIN\`) && (PathPrefix(\`/signalexchange.SignalExchange/\`) || PathPrefix(\`/management.ManagementService/\`))
      - traefik.http.routers.auroranet-grpc.entrypoints=$TRAEFIK_ENTRYPOINT
      - traefik.http.routers.auroranet-grpc.tls=true
$(if [[ -n "$tls_labels" ]]; then echo "      - traefik.http.routers.auroranet-grpc.${tls_labels}"; fi)
      - traefik.http.routers.auroranet-grpc.service=auroranet-server-h2c
      # Backend router (relay, WebSocket, API, OAuth2)
      - traefik.http.routers.auroranet-backend.rule=Host(\`$AURORANET_DOMAIN\`) && (PathPrefix(\`/relay\`) || PathPrefix(\`/ws-proxy/\`) || PathPrefix(\`/api\`) || PathPrefix(\`/oauth2\`))
      - traefik.http.routers.auroranet-backend.entrypoints=$TRAEFIK_ENTRYPOINT
      - traefik.http.routers.auroranet-backend.tls=true
$(if [[ -n "$tls_labels" ]]; then echo "      - traefik.http.routers.auroranet-backend.${tls_labels}"; fi)
      - traefik.http.routers.auroranet-backend.service=auroranet-server
      # Services
      - traefik.http.services.auroranet-server.loadbalancer.server.port=80
      - traefik.http.services.auroranet-server-h2c.loadbalancer.server.port=80
      - traefik.http.services.auroranet-server-h2c.loadbalancer.server.scheme=h2c
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

volumes:
  auroranet_data:

networks:
  $network_name:
$network_config
EOF
  return 0
}

render_docker_compose_exposed_ports() {
  local bind_addr=$(get_bind_address)
  local networks="[auroranet]"
  local networks_config="networks:
  auroranet:"

  # If an external network is specified, add it and include in service networks
  if [[ -n "$EXTERNAL_PROXY_NETWORK" ]]; then
    networks="[auroranet, $EXTERNAL_PROXY_NETWORK]"
    networks_config="networks:
  auroranet:
  $EXTERNAL_PROXY_NETWORK:
    external: true"
  fi

  cat <<EOF
services:
  # UI dashboard
  dashboard:
    image: $DASHBOARD_IMAGE
    container_name: auroranet-dashboard
    restart: unless-stopped
    networks: ${networks}
    ports:
      - '${bind_addr}:${DASHBOARD_HOST_PORT}:80'
    env_file:
      - ./dashboard.env
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Combined server (Management + Signal + Relay + STUN)
  auroranet-server:
    image: $AURORANET_SERVER_IMAGE
    container_name: auroranet-server
    restart: unless-stopped
    networks: ${networks}
    ports:
      - '${bind_addr}:${MANAGEMENT_HOST_PORT}:80'
      - '$AURORANET_STUN_PORT:$AURORANET_STUN_PORT/udp'
    volumes:
      - auroranet_data:/var/lib/auroranet
      - ./config.yaml:/etc/auroranet/config.yaml
    command: ["--config", "/etc/auroranet/config.yaml"]
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

volumes:
  auroranet_data:

${networks_config}
EOF
  return 0
}

render_nginx_conf() {
  local upstream_host=$(get_upstream_host)
  local dashboard_addr="${upstream_host}:${DASHBOARD_HOST_PORT}"
  local server_addr="${upstream_host}:${MANAGEMENT_HOST_PORT}"
  local install_note="# 1. Update SSL certificate paths below
# 2. Copy to your nginx config directory:
#    Debian/Ubuntu: /etc/nginx/sites-available/auroranet (then symlink to sites-enabled)
#    RHEL/CentOS:   /etc/nginx/conf.d/auroranet.conf
# 3. Test and reload: nginx -t && systemctl reload nginx"

  # If running in Docker network, use container names
  if [[ -n "$EXTERNAL_PROXY_NETWORK" ]]; then
    dashboard_addr="auroranet-dashboard:80"
    server_addr="auroranet-server:80"
    install_note="# This config uses container names since Nginx is on the same Docker network.
# Add this to your nginx.conf or include it from a separate file."
  fi

  cat <<EOF
# AuroraNet Nginx Configuration
# Generated by getting-started.sh
#
${install_note}

upstream auroranet_dashboard {
    server ${dashboard_addr};
    keepalive 10;
}
upstream auroranet_server {
    server ${server_addr};
}

server {
    listen 80;
    server_name $AURORANET_DOMAIN;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $AURORANET_DOMAIN;

    # SSL/TLS Configuration
    # Update these paths based on your certificate source:
    #
    # Let's Encrypt (certbot):
    #   ssl_certificate /etc/letsencrypt/live/$AURORANET_DOMAIN/fullchain.pem;
    #   ssl_certificate_key /etc/letsencrypt/live/$AURORANET_DOMAIN/privkey.pem;
    #
    # Let's Encrypt (acme.sh):
    #   ssl_certificate /root/.acme.sh/$AURORANET_DOMAIN/fullchain.cer;
    #   ssl_certificate_key /root/.acme.sh/$AURORANET_DOMAIN/$AURORANET_DOMAIN.key;
    #
    # Custom certificates:
    #   ssl_certificate /etc/ssl/certs/$AURORANET_DOMAIN.crt;
    #   ssl_certificate_key /etc/ssl/private/$AURORANET_DOMAIN.key;
    #
    ssl_certificate /path/to/your/fullchain.pem;
    ssl_certificate_key /path/to/your/privkey.pem;

    # Recommended SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;

    # Required for long-lived gRPC connections
    client_header_timeout 1d;
    client_body_timeout 1d;

    # Common proxy headers
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Scheme \$scheme;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host \$host;
    grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

    # WebSocket connections (relay, signal, management)
    location ~ ^/(relay|ws-proxy/) {
        proxy_pass http://auroranet_server;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 1d;
    }

    # Native gRPC (signal + management)
    location ~ ^/(signalexchange\.SignalExchange|management\.ManagementService)/ {
        grpc_pass grpc://auroranet_server;
        grpc_read_timeout 1d;
        grpc_send_timeout 1d;
        grpc_socket_keepalive on;
    }

    # HTTP routes (API + OAuth2)
    location ~ ^/(api|oauth2)/ {
        proxy_pass http://auroranet_server;
        proxy_set_header Host \$host;
    }

    # Dashboard (catch-all)
    location / {
        proxy_pass http://auroranet_dashboard;
    }
}
EOF
  return 0
}

render_external_caddyfile() {
  local upstream_host=$(get_upstream_host)
  local dashboard_addr="${upstream_host}:${DASHBOARD_HOST_PORT}"
  local server_addr="${upstream_host}:${MANAGEMENT_HOST_PORT}"
  local install_note="# Add this block to your existing Caddyfile and reload Caddy"

  # If running in Docker network, use container names
  if [[ -n "$EXTERNAL_PROXY_NETWORK" ]]; then
    dashboard_addr="auroranet-dashboard:80"
    server_addr="auroranet-server:80"
    install_note="# This config uses container names since Caddy is on the same Docker network.
# Add this block to your Caddyfile and reload Caddy."
  fi

  cat <<EOF
# AuroraNet Caddyfile Snippet
# Generated by getting-started.sh
#
${install_note}

$AURORANET_DOMAIN {
    # Native gRPC (needs HTTP/2 cleartext to backend)
    @grpc header Content-Type application/grpc*
    reverse_proxy @grpc h2c://${server_addr}

    # Combined server paths (relay, signal, management, OAuth2)
    @backend path /relay* /ws-proxy/* /api/* /oauth2/*
    reverse_proxy @backend ${server_addr}

    # Dashboard (everything else)
    reverse_proxy /* ${dashboard_addr}
}
EOF
  return 0
}

render_npm_advanced_config() {
  local upstream_host=$(get_upstream_host)
  local server_addr="${upstream_host}:${MANAGEMENT_HOST_PORT}"

  # If external network is specified, use container names instead of host addresses
  if [[ -n "$EXTERNAL_PROXY_NETWORK" ]]; then
    server_addr="auroranet-server:80"
  fi

  cat <<EOF
# Advanced Configuration for Nginx Proxy Manager
# Paste this into the "Advanced" tab of your Proxy Host configuration
#
# IMPORTANT: Enable "HTTP/2 Support" in the SSL tab for gRPC to work!

# Required for long-lived connections (gRPC and WebSocket)
client_header_timeout 1d;
client_body_timeout 1d;

# WebSocket connections (relay, signal, management)
location ~ ^/(relay|ws-proxy/) {
    proxy_pass http://${server_addr};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 1d;
}

# Native gRPC (signal + management)
location ~ ^/(signalexchange\.SignalExchange|management\.ManagementService)/ {
    grpc_pass grpc://${server_addr};
    # Overwrite rather than pass through: without this the client's own
    # x-forwarded-for metadata reaches AuroraNet as the connection IP.
    grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    grpc_read_timeout 1d;
    grpc_send_timeout 1d;
    grpc_socket_keepalive on;
}

# HTTP routes (API + OAuth2)
location ~ ^/(api|oauth2)/ {
    proxy_pass http://${server_addr};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
EOF
  return 0
}

############################################
# Post-Setup Instructions per Proxy Type
############################################

print_builtin_traefik_instructions() {
  echo ""
  echo "$MSG_SEPARATOR"
  echo "  AURORANET SETUP COMPLETE"
  echo "$MSG_SEPARATOR"
  echo ""
  echo "You can access the AuroraNet dashboard at:"
  echo "  $AURORANET_HTTP_PROTOCOL://$AURORANET_DOMAIN"
  echo ""
  echo "Follow the onboarding steps to set up your AuroraNet instance."
  echo ""
  echo "Traefik is handling TLS certificates automatically via Let's Encrypt."
  echo "If you see certificate warnings, wait a moment for certificate issuance to complete."
  echo ""
  echo "Open ports:"
  echo "  - 443/tcp   (HTTPS - all AuroraNet services)"
  echo "  - 80/tcp    (HTTP - redirects to HTTPS)"
  echo "  - $AURORANET_STUN_PORT/udp   (STUN - required for NAT traversal)"
  if [[ "$ENABLE_PROXY" == "true" ]]; then
    echo "  - 51820/udp (WIREGUARD - (optional) for P2P proxy connections)"
  fi
  echo ""
  if [[ "${AURORANET_AGENT_NETWORK}" == "true" ]]; then
    echo "For enterprise environments requiring high availability and advanced integrations,"
    echo "consider a commercial on-prem license:"
    echo ""
    echo "  Commercial license: https://auroranet.ai/pricing"
    echo "  Documentation: https://docs.aurora-net.org/agent-network"
  else
    echo "This setup is ideal for homelabs and smaller organization deployments."
    echo "For enterprise environments requiring high availability and advanced integrations,"
    echo "consider a commercial on-prem license or scaling your open source deployment:"
    echo ""
    echo "  Commercial license: https://aurora-net.org/pricing#on-prem"
    echo "  Scaling guide:      https://docs.aurora-net.org/scaling-your-self-hosted-deployment"
  fi
  echo ""
  if [[ "$ENABLE_PROXY" == "true" ]]; then
    echo "AuroraNet Proxy:"
    echo "  The proxy service is enabled and running."
    echo "  Any domain NOT matching $AURORANET_DOMAIN will be passed through to the proxy."
    echo "  The proxy handles its own TLS certificates via ACME TLS-ALPN-01 challenge."
    echo "  Point your proxy domain to this server's domain address like in the examples below:"
    echo ""
    echo "  *.$AURORANET_DOMAIN    CNAME    $AURORANET_DOMAIN"
    echo ""
    if [[ "$ENABLE_CROWDSEC" == "true" ]]; then
      echo "CrowdSec IP Reputation:"
      echo "  CrowdSec LAPI is running and connected to the community blocklist."
      echo "  The proxy will automatically check client IPs against known threats."
      echo "  Enable CrowdSec per-service in the dashboard under Access Control."
      echo ""
      echo "  To enroll in CrowdSec Console (optional, for dashboard and premium blocklists):"
      echo "    docker exec auroranet-crowdsec cscli console enroll <your-enrollment-key>"
      echo "  Get your enrollment key at: https://app.crowdsec.net"
      echo ""
    fi
    if [[ "$ENABLE_CROWDSEC_APPSEC" == "true" ]]; then
      echo "CrowdSec AppSec:"
      echo "  The dashboard, /api, and /oauth2 are inspected."
      echo "  Once Traefik is up, a request for /.env should return 403."
      echo "  The first Traefik start downloads the CrowdSec bouncer plugin."
      echo "  If you are locked out, recover over SSH. See:"
      echo "    https://docs.aurora-net.org/selfhosted/maintenance/crowdsec-dashboard#recovering-from-a-dashboard-lockout"
      echo ""
    fi
  fi
  if [[ "${AURORANET_AGENT_NETWORK}" == "true" ]]; then
    echo "Note: The public domain is only for setting up secure connections."
    echo "Your APIs and agent services remain private and are never exposed publicly."
    echo ""
  fi
  return 0
}

print_traefik_instructions() {
  echo ""
  echo "$MSG_SEPARATOR"
  echo "  TRAEFIK SETUP"
  echo "$MSG_SEPARATOR"
  echo ""
  echo "AuroraNet containers are configured with Traefik labels."
  echo ""
  echo "Configuration:"
  echo "  Entrypoint: $TRAEFIK_ENTRYPOINT"
  if [[ -n "$TRAEFIK_CERTRESOLVER" ]]; then
    echo "  Certificate resolver: $TRAEFIK_CERTRESOLVER"
  fi
  if [[ -n "$TRAEFIK_EXTERNAL_NETWORK" ]]; then
    echo "  Network: $TRAEFIK_EXTERNAL_NETWORK (external)"
  else
    echo "  Network: auroranet"
  fi
  echo ""
  echo "$MSG_NEXT_STEPS"
  echo "  - Ensure Traefik is running and configured"
  if [[ -n "$TRAEFIK_EXTERNAL_NETWORK" ]]; then
    echo "  - Traefik must be on the '$TRAEFIK_EXTERNAL_NETWORK' network"
  fi
  echo "  - Entrypoint '$TRAEFIK_ENTRYPOINT' must be defined"
  if [[ -n "$TRAEFIK_CERTRESOLVER" ]]; then
    echo "  - Certificate resolver '$TRAEFIK_CERTRESOLVER' must be configured"
  fi
  echo "  - Disable read timeout on the entrypoint for gRPC streams:"
  echo "    --entrypoints.$TRAEFIK_ENTRYPOINT.transport.respondingTimeouts.readTimeout=0"
  echo "  - HTTP to HTTPS redirect (recommended)"
  return 0
}

print_nginx_instructions() {
  local bind_addr=$(get_bind_address)
  echo ""
  echo "$MSG_SEPARATOR"
  echo "  NGINX SETUP"
  echo "$MSG_SEPARATOR"
  echo ""
  echo "Generated: nginx-auroranet.conf"
  echo ""
  echo "IMPORTANT: Nginx requires manual TLS certificate setup."
  echo "You'll need to obtain SSL/TLS certificates and configure the paths in the"
  echo "generated config file. The config includes examples for common certificate sources."
  echo ""
  if [[ -n "$EXTERNAL_PROXY_NETWORK" ]]; then
    echo "AuroraNet containers have joined the '$EXTERNAL_PROXY_NETWORK' Docker network."
    echo "The config uses container names for upstream servers."
    echo ""
    echo "$MSG_NEXT_STEPS"
    echo "  1. Ensure your Nginx container has access to SSL certificates"
    echo "     (mount certificate directory as volume if needed)"
    echo "  2. Edit nginx-auroranet.conf and update SSL certificate paths"
    echo "     The config includes examples for certbot, acme.sh, and custom certs"
    echo "  3. Include the config in your Nginx container's configuration"
    echo "  4. Reload Nginx"
  else
    echo "$MSG_NEXT_STEPS"
    echo "  1. Obtain SSL/TLS certificates (Let's Encrypt recommended)"
    echo "  2. Edit nginx-auroranet.conf and update certificate paths"
    echo "  3. Install to /etc/nginx/sites-available/ (Debian) or /etc/nginx/conf.d/ (RHEL)"
    echo "  4. Test and reload: nginx -t && systemctl reload nginx"
    echo ""
    echo "For detailed TLS setup instructions, see:"
    echo "https://docs.aurora-net.org/selfhosted/reverse-proxy#tls-certificate-setup-for-nginx"
    echo ""
    echo "Container ports (bound to ${bind_addr}):"
    echo "  Dashboard:     ${DASHBOARD_HOST_PORT}"
    echo "  AuroraNet Server: ${MANAGEMENT_HOST_PORT} (all services)"
  fi
  return 0
}

print_npm_instructions() {
  local bind_addr=$(get_bind_address)
  local upstream_host=$(get_upstream_host)
  echo ""
  echo "$MSG_SEPARATOR"
  echo "  NGINX PROXY MANAGER SETUP"
  echo "$MSG_SEPARATOR"
  echo ""
  echo "Generated: npm-advanced-config.txt"
  echo ""
  if [[ -n "$EXTERNAL_PROXY_NETWORK" ]]; then
    echo "AuroraNet containers have joined the '$EXTERNAL_PROXY_NETWORK' Docker network."
    echo ""
    echo "In NPM, create a Proxy Host:"
    echo "  Domain: $AURORANET_DOMAIN"
    echo "  Forward Hostname: auroranet-dashboard"
    echo "  Forward Port: 80"
    echo "  Block Common Exploits: enabled"
    echo ""
    echo "  SSL tab:"
    echo "    - Request or select existing certificate"
    echo "    - Enable 'HTTP/2 Support' (REQUIRED for gRPC)"
    echo ""
    echo "  Advanced tab:"
    echo "    - Paste contents of npm-advanced-config.txt"
  else
    echo "Container ports (bound to ${bind_addr}):"
    echo "  Dashboard:     ${DASHBOARD_HOST_PORT}"
    echo "  AuroraNet Server: ${MANAGEMENT_HOST_PORT} (all services)"
    echo ""
    echo "In NPM, create a Proxy Host:"
    echo "  Domain: $AURORANET_DOMAIN"
    echo "  Forward Hostname/IP: ${upstream_host}"
    echo "  Forward Port: ${DASHBOARD_HOST_PORT}"
    echo "  Block Common Exploits: enabled"
    echo ""
    echo "  SSL tab:"
    echo "    - Request or select existing certificate"
    echo "    - Enable 'HTTP/2 Support' (REQUIRED for gRPC)"
    echo ""
    echo "  Advanced tab:"
    echo "    - Paste contents of npm-advanced-config.txt"
  fi
  return 0
}

print_external_caddy_instructions() {
  local bind_addr=$(get_bind_address)
  echo ""
  echo "$MSG_SEPARATOR"
  echo "  EXTERNAL CADDY SETUP"
  echo "$MSG_SEPARATOR"
  echo ""
  echo "Generated: caddyfile-auroranet.txt"
  echo ""
  if [[ -n "$EXTERNAL_PROXY_NETWORK" ]]; then
    echo "AuroraNet containers have joined the '$EXTERNAL_PROXY_NETWORK' Docker network."
    echo "The config uses container names for upstream servers."
    echo ""
    echo "$MSG_NEXT_STEPS"
    echo "  1. Add the contents of caddyfile-auroranet.txt to your Caddyfile"
    echo "  2. Reload Caddy"
  else
    echo "$MSG_NEXT_STEPS"
    echo "  1. Add the contents of caddyfile-auroranet.txt to your Caddyfile"
    echo "  2. Reload Caddy: caddy reload --config /path/to/Caddyfile"
    echo ""
    echo "Container ports (bound to ${bind_addr}):"
    echo "  Dashboard:     ${DASHBOARD_HOST_PORT}"
    echo "  AuroraNet Server: ${MANAGEMENT_HOST_PORT} (all services)"
  fi
  return 0
}

print_manual_instructions() {
  local bind_addr=$(get_bind_address)
  local upstream_host=$(get_upstream_host)
  echo ""
  echo "$MSG_SEPARATOR"
  echo "  MANUAL REVERSE PROXY SETUP"
  echo "$MSG_SEPARATOR"
  echo ""
  echo "Container ports (bound to ${bind_addr}):"
  echo "  Dashboard:     ${DASHBOARD_HOST_PORT}"
  echo "  AuroraNet Server: ${MANAGEMENT_HOST_PORT} (all services: management, signal, relay)"
  echo ""
  echo "Configure your reverse proxy with these routes (all go to the same backend):"
  echo ""
  echo "  WebSocket (relay, signal, management WS proxy):"
  echo "    /relay*, /ws-proxy/*           -> ${upstream_host}:${MANAGEMENT_HOST_PORT}"
  echo "    (HTTP with WebSocket upgrade, extended timeout)"
  echo ""
  echo "  Native gRPC (signal + management):"
  echo "    /signalexchange.SignalExchange/* -> ${upstream_host}:${MANAGEMENT_HOST_PORT}"
  echo "    /management.ManagementService/* -> ${upstream_host}:${MANAGEMENT_HOST_PORT}"
  echo "    (gRPC/h2c - plaintext HTTP/2)"
  echo ""
  echo "  HTTP (API + embedded IdP):"
  echo "    /api/*, /oauth2/*              -> ${upstream_host}:${MANAGEMENT_HOST_PORT}"
  echo ""
  echo "  Dashboard (catch-all):"
  echo "    /*                             -> ${upstream_host}:${DASHBOARD_HOST_PORT}"
  echo ""
  echo "IMPORTANT: gRPC routes require HTTP/2 (h2c) upstream support."
  echo "WebSocket and gRPC connections need extended timeouts (recommend 1 day)."
  return 0
}

print_post_setup_instructions() {
  case "$REVERSE_PROXY_TYPE" in
    0)
      print_builtin_traefik_instructions
      ;;
    1)
      print_traefik_instructions
      ;;
    2)
      print_nginx_instructions
      ;;
    3)
      print_npm_instructions
      ;;
    4)
      print_external_caddy_instructions
      ;;
    5)
      print_manual_instructions
      ;;
    *)
      echo "Unknown reverse proxy type: $REVERSE_PROXY_TYPE" > /dev/stderr
      ;;
  esac
  return 0
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  init_environment
fi
