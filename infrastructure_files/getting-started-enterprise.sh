#!/bin/bash

# AuroraNet Enterprise — Getting Started
# Single-node bootstrap for a self-hosted AuroraNet Enterprise stack with the
# embedded identity provider. Owner is created via first-login flow.
# Add features to an existing install with --enable-proxy or --enable-traffic-events.

SED_STRIP_PADDING='s/=//g'

AURORANET_EULA_URL="https://aurora-net.org/self-hosted-EULA"

STACK_FILES=(.env docker-compose.yml config.yaml)

# Host directory of a custom TLS certificate mounted at /certs, see
# https://docs.aurora-net.org/selfhosted/enterprise/getting-started#appendix-using-a-custom-tls-certificate
CUSTOM_TLS_CERTS=""
PROXY_TOKEN_ID=""
APPSEC_ACQUIS_CREATED=""

# Static IP for Traefik inside the compose bridge network. The management
# server trusts X-Forwarded-* headers from this address only.
TRAEFIK_IP="172.30.0.10"

TRAEFIK_HEADER_CONFIG='      - "--entrypoints.web.http.aliasHeadersStrategy=delete"
      - "--entrypoints.websecure.http.aliasHeadersStrategy=delete"'

# v1.7.1 is the bouncer plugin release validated with CrowdSec 1.8.1 and Traefik 3.7.14.
TRAEFIK_APPSEC_PLUGIN_CONFIG='      - "--experimental.plugins.bouncer.modulename=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
      - "--experimental.plugins.bouncer.version=v1.7.1"'

LICENSE_VERDICT="unknown"
LICENSE_LOG_LINES=""

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

check_openssl() {
  if ! command -v openssl &> /dev/null; then
    echo "openssl is not installed or not in PATH." > /dev/stderr
    exit 1
  fi
  return
}

# Only parseable versions can guarantee that aliasHeadersStrategy and its
# CVE-2026-88004 fix (v3.7.13) are available in the fresh-install compose.
check_traefik_tag() {
  local tag="${AURORANET_TRAEFIK_TAG:-}" ver major minor patch
  [[ -n "$tag" ]] || return 0
  ver="${tag#v}"
  if [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))?$ ]]; then
    die "Cannot verify AURORANET_TRAEFIK_TAG=$tag. Use a numeric version tag such as v3.7.13 or newer, or unset AURORANET_TRAEFIK_TAG for the default (v3.7.18)."
  fi
  major=$((10#${BASH_REMATCH[1]}))
  minor=$((10#${BASH_REMATCH[2]}))
  patch=$((10#${BASH_REMATCH[4]:-0}))
  if (( major < 3 || (major == 3 && minor < 7) || (major == 3 && minor == 7 && patch < 13) )); then
    die "AURORANET_TRAEFIK_TAG=$tag predates aliasHeadersStrategy and its CVE-2026-88004 fix (added in v3.7.12, fixed in v3.7.13), which this installer always enables. Use v3.7.13 or newer, or unset AURORANET_TRAEFIK_TAG for the default (v3.7.18)."
  fi
  return
}

die() {
  echo "$1" > /dev/stderr
  exit 1
}

# env_get KEY [DEFAULT] prints KEY's value from .env, or DEFAULT if unset.
env_get() {
  local value
  value=$(sed -n "s/^$1=//p" .env | tail -n 1)
  echo "${value:-$2}"
  return
}

# merge_env upserts the KEY=VALUE lines from stdin into .env, in place.
merge_env() {
  local merged
  merged=$(awk -F= 'NR == FNR { v[$1] = $0; o[++n] = $1; next }
    $1 in v { print v[$1]; delete v[$1]; next }
    { print }
    END { for (i = 1; i <= n; i++) if (o[i] in v) print v[o[i]] }' - .env)
  printf '%s\n' "$merged" > .env
  return
}

rand_secret() {
  openssl rand -base64 32 | sed "$SED_STRIP_PADDING"
  return
}

rand_b64_key() {
  openssl rand -base64 32
  return
}

check_nb_domain() {
  local domain="$1"
  if [[ -z "$domain" ]]; then
    echo "The domain cannot be empty." > /dev/stderr
    return 1
  fi
  if [[ "$domain" == "auroranet.example.com" ]]; then
    echo "The domain cannot be auroranet.example.com" > /dev/stderr
    return 1
  fi
  if [[ "$domain" =~ ^[0-9.]+$ ]]; then
    echo "An IP address is not allowed. A real DNS-resolvable domain is required for TLS and the embedded IdP issuer." > /dev/stderr
    return 1
  fi
  if [[ ! "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
    echo "The value '$domain' is not a valid FQDN. A real DNS-resolvable domain is required for TLS and the embedded IdP issuer." > /dev/stderr
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

read_nb_domain() {
  local value=""
  echo -n "Enter the FQDN for AuroraNet (must resolve via DNS, e.g. auroranet.my-domain.com): " > /dev/stderr
  read -r value < /dev/tty
  if ! check_nb_domain "$value"; then
    read_nb_domain
    return
  fi
  if ! check_domain_resolves "$value"; then
    echo "" > /dev/stderr
    echo "Warning: '$value' does not resolve via DNS from this host." > /dev/stderr
    echo "Traefik will not be able to issue TLS certificates until it does." > /dev/stderr
    local confirm=""
    echo -n "Continue anyway? [y/N]: " > /dev/stderr
    read -r confirm < /dev/tty
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      read_nb_domain
      return
    fi
  fi
  echo "$value"
  return
}

read_letsencrypt_email() {
  if [[ -n "${AURORANET_LETSENCRYPT_EMAIL:-}" ]]; then
    echo "$AURORANET_LETSENCRYPT_EMAIL"
    return
  fi
  local value=""
  echo "Enter your email for Let's Encrypt certificate notifications." > /dev/stderr
  echo -n "Email address: " > /dev/stderr
  read -r value < /dev/tty
  if [[ -z "$value" ]]; then
    echo "Email is required for Let's Encrypt." > /dev/stderr
    read_letsencrypt_email
    return
  fi
  echo "$value"
  return
}

read_required() {
  local prompt="$1"
  local value=""
  while [[ -z "$value" ]]; do
    echo -n "$prompt: " > /dev/stderr
    read -r value < /dev/tty
    if [[ -z "$value" ]]; then
      echo "Value cannot be empty." > /dev/stderr
    fi
  done
  echo "$value"
  return
}

read_secret() {
  local prompt="$1"
  local value=""
  while [[ -z "$value" ]]; do
    echo -n "$prompt: " > /dev/stderr
    read -rs value < /dev/tty
    echo "" > /dev/stderr
    if [[ -z "$value" ]]; then
      echo "Value cannot be empty." > /dev/stderr
    fi
  done
  echo "$value"
  return
}

# read_yes_no "<prompt>" [<default y|n>]
read_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local hint
  if [[ "$default" == "y" ]]; then
    hint="[Y/n]"
  else
    hint="[y/N]"
  fi
  echo -n "${prompt} ${hint}: " > /dev/stderr
  local ans=""
  read -r ans < /dev/tty
  if [[ -z "$ans" ]]; then
    ans="$default"
  fi
  case "$ans" in
    [Yy] | [Yy][Ee][Ss]) echo "yes" ;;
    *) echo "no" ;;
  esac
  return
}

read_crowdsec_appsec_option() {
  echo ""
  echo "CrowdSec AppSec:"
  echo "  Inspects requests to the dashboard, /api, and /oauth2 and blocks common"
  echo "  web attack patterns. Relay, gRPC, and proxied services are not inspected."
  echo "  If CrowdSec is unreachable, those paths are blocked. Two different rule"
  echo "  matches from your IP within a minute can lock you out of the dashboard"
  echo "  for 4 hours. Recovery is over SSH."
  AURORANET_CROWDSEC_APPSEC=$(read_yes_no "Enable AppSec" "n")
  return
}

read_crowdsec_option() {
  echo ""
  echo "CrowdSec:"
  echo "  Checks client IPs against a community threat intelligence database and"
  echo "  blocks known malicious sources before they reach services exposed through"
  echo "  the proxy. Adds a CrowdSec container to the stack."
  AURORANET_CROWDSEC=$(read_yes_no "Enable CrowdSec" "n")
  AURORANET_CROWDSEC_APPSEC="no"
  if [[ "$AURORANET_CROWDSEC" == "yes" ]]; then
    read_crowdsec_appsec_option
  fi
  return
}

# Port 7422 stays closed unless this file exists before the container is
# created. Traefik waits on a health check that opens that port.
write_crowdsec_appsec_acquisition() {
  if [[ -f crowdsec/acquis.d/appsec.yaml ]]; then
    return
  fi
  mkdir -p crowdsec/acquis.d
  APPSEC_ACQUIS_CREATED="crowdsec/acquis.d/appsec.yaml"
  cat > crowdsec/acquis.d/appsec.yaml <<'EOF'
appsec_configs:
  - crowdsecurity/appsec-default
labels:
  type: appsec
listen_addr: 0.0.0.0:7422
source: appsec
EOF
  return
}

# ensure_crowdsec_dashboard_key mints the Traefik bouncer key when AppSec is on
# and .env does not already have one. The proxy bouncer key is a different key.
ensure_crowdsec_dashboard_key() {
  CROWDSEC_DASHBOARD_BOUNCER_KEY=""
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" != "yes" ]]; then
    return
  fi
  if [[ -f .env && -n "$(env_get CROWDSEC_DASHBOARD_BOUNCER_KEY)" ]]; then
    return
  fi
  CROWDSEC_DASHBOARD_BOUNCER_KEY=$(openssl rand -hex 32) || die "Could not generate the CrowdSec dashboard bouncer key."
  if [[ -z "$CROWDSEC_DASHBOARD_BOUNCER_KEY" ]]; then
    die "Could not generate the CrowdSec dashboard bouncer key."
  fi
  return
}

# Gate the install on explicit acceptance of the AuroraNet On-Premise EULA.
require_eula_acceptance() {
  cat > /dev/stderr <<EOF

  ──────────────────────────────────────────────────────────────────────
   AuroraNet On-Premise End User License Agreement
  ──────────────────────────────────────────────────────────────────────
  AuroraNet's on-premise software is commercial software, licensed and not
  sold. Your installation, deployment and use are governed by the AuroraNet
  On-Premise End User License Agreement (the "EULA"). Please read the EULA
  in full before continuing:

      ${AURORANET_EULA_URL}

  By typing "accept" and continuing the installation, you confirm that you
  have read and agree to the EULA, that you are authorized to accept it on
  behalf of your organization (the "Customer"), and that the Software is
  used for business purposes only.
  ──────────────────────────────────────────────────────────────────────
EOF

  if [[ "${NB_ACCEPT_EULA:-}" == "yes" ]]; then
    echo "EULA accepted via NB_ACCEPT_EULA=yes." > /dev/stderr
    return 0
  fi

  local ans=""
  echo -n 'Type "accept" to agree, or anything else to abort: ' > /dev/stderr
  read -r ans < /dev/tty
  if [[ "$ans" != "accept" ]]; then
    echo "" > /dev/stderr
    echo "EULA not accepted. Aborting installation." > /dev/stderr
    exit 1
  fi
  echo "" > /dev/stderr
  return
}

wait_postgres() {
  set +e
  echo -n "Waiting for postgres to become ready"
  local counter=1
  while true; do
    if $DOCKER_COMPOSE_COMMAND exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &> /dev/null; then
      break
    fi
    if [[ $counter -eq 60 ]]; then
      echo ""
      echo "Postgres is taking too long. Recent logs:"
      $DOCKER_COMPOSE_COMMAND logs --tail=20 postgres
      exit 1
    fi
    echo -n " ."
    sleep 2
    counter=$((counter + 1))
  done
  echo " done"
  set -e
  return
}

wait_for_license_verdict() {
  local counter=0
  local logs=""

  echo -n "Waiting for the server to validate the license"
  while [[ $counter -lt 60 ]]; do
    logs=$($DOCKER_COMPOSE_COMMAND logs --no-color --tail=all auroranet-server 2>/dev/null || true)

    if grep -qi "license invalidated" <<< "$logs"; then
      echo " rejected"
      LICENSE_VERDICT="rejected"
      LICENSE_LOG_LINES=$(grep -i "license" <<< "$logs" | tail -n 5 || true)
      return 0
    fi

    if grep -qi "license validated" <<< "$logs"; then
      echo " ok"
      LICENSE_VERDICT="ok"
      return 0
    fi

    echo -n " ."
    sleep 2
    counter=$((counter + 1))
  done

  echo " no verdict in 120s"
  LICENSE_VERDICT="unknown"
  LICENSE_LOG_LINES=$(grep -iE "failed to validate license|error validating license" <<< "$logs" | tail -n 3 || true)
  return 0
}

report_license_verdict() {
  if [[ "$LICENSE_VERDICT" == "ok" ]]; then
    return 0
  fi

  if [[ "$LICENSE_VERDICT" == "unknown" ]]; then
    echo ""
    echo "  ⚠  The server logged no license verdict within 120s."
    if [[ -n "$LICENSE_LOG_LINES" ]]; then
      echo "     It was still reporting validation errors:"
      while IFS= read -r line; do
        [[ -n "$line" ]] && echo "     $line"
      done <<< "$LICENSE_LOG_LINES"
    fi
    echo ""
    echo "     Check the verdict with:"
    echo ""
    echo "       $DOCKER_COMPOSE_COMMAND logs auroranet-server | grep -i license"
    return 0
  fi

  local unreachable="false"
  if grep -qi "couldn't be validated with the license server" <<< "$LICENSE_LOG_LINES"; then
    unreachable="true"
  fi

  echo ""
  if [[ "$unreachable" == "true" ]]; then
    echo "  ⚠  The server could not validate the license:"
  else
    echo "  ⚠  The server rejected the license key:"
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "     $line"
  done <<< "$LICENSE_LOG_LINES"
  echo ""
  echo "     The stack is up, and only the license check did not pass."
  echo ""
  if [[ "$unreachable" == "true" ]]; then
    echo "     The license server could not be reached, so the key itself was"
    echo "     never checked. Confirm this host has outbound access to the"
    echo "     license server, then restart:"
  else
    echo "     Check the reason the server gave above, verify that"
    echo "     AURORANET_LICENSE_KEY in .env matches the key you were issued,"
    echo "     then restart:"
  fi
  echo ""
  echo "       $DOCKER_COMPOSE_COMMAND up -d"
  return 0
}

# up_all_but_proxy skips the proxy, which needs a token from the running server.
up_all_but_proxy() {
  local services
  services=$($DOCKER_COMPOSE_COMMAND config --services | grep -vx proxy)
  # shellcheck disable=SC2086
  $DOCKER_COMPOSE_COMMAND up -d $services
  return
}

wait_crowdsec() {
  $DOCKER_COMPOSE_COMMAND up -d crowdsec || return 1
  for _ in {1..60}; do
    $DOCKER_COMPOSE_COMMAND exec -T crowdsec cscli lapi status &> /dev/null && return 0
    sleep 2
  done
  return 1
}

admin_token() {
  $DOCKER_COMPOSE_COMMAND run --rm --no-deps -T auroranet-server admin token "$@" --config /etc/auroranet/config.yaml
  return
}

# revoke_proxy_token revokes the token this run minted if the proxy never started.
# On failure the ID is kept, so rollback retries it.
revoke_proxy_token() {
  [[ -n "$PROXY_TOKEN_ID" ]] || return 0
  if admin_token revoke "$PROXY_TOKEN_ID" > /dev/null; then
    PROXY_TOKEN_ID=""
    return 0
  fi
  echo "Could not revoke the unused proxy token ${PROXY_TOKEN_ID}. Revoke it with:" > /dev/stderr
  echo "  $DOCKER_COMPOSE_COMMAND run --rm auroranet-server admin token revoke ${PROXY_TOKEN_ID} --config /etc/auroranet/config.yaml" > /dev/stderr
  return
}

# start_proxy mints the proxy token and CrowdSec bouncer key, then starts the proxy.
start_proxy() {
  local out token key
  echo "Creating the proxy access token ..."
  out=$(admin_token create --name default-proxy) || true
  token=$(awk '/^Token:/ {print $2}' <<< "$out")
  PROXY_TOKEN_ID=$(awk '/^Token ID:/ {print $3}' <<< "$out")
  [[ -n "$token" ]] || die "Could not create the proxy access token. Check the auroranet-server logs, then re-run with --enable-proxy."

  if [[ "$AURORANET_CROWDSEC" == "yes" ]]; then
    echo "Registering the CrowdSec bouncer ..."
    if wait_crowdsec; then
      # "add" fails if an earlier attempt already registered the bouncer.
      $DOCKER_COMPOSE_COMMAND exec -T crowdsec cscli bouncers delete auroranet-proxy &> /dev/null || true
      key=$($DOCKER_COMPOSE_COMMAND exec -T crowdsec cscli bouncers add auroranet-proxy -o raw) || true
    fi
    if [[ -z "$key" ]]; then
      revoke_proxy_token
      die "Could not register the CrowdSec bouncer. Check the crowdsec logs, then re-run with --enable-proxy."
    fi
  fi

  # A stored token marks the proxy as set up, so it is cleared again on failure.
  {
    echo "AURORANET_PROXY_TOKEN=${token}"
    if [[ -n "$key" ]]; then echo "AURORANET_CROWDSEC_BOUNCER_KEY=${key}"; fi
  } | merge_env
  if ! $DOCKER_COMPOSE_COMMAND up -d proxy; then
    revoke_proxy_token
    echo "AURORANET_PROXY_TOKEN=" | merge_env
    die "Could not start the proxy. Check the proxy logs, then re-run with --enable-proxy."
  fi
  PROXY_TOKEN_ID=""
  return
}

print_proxy_notes() {
  echo ""
  echo "AuroraNet Proxy:"
  echo "  Every domain other than ${AURORANET_DOMAIN} is passed through to the proxy,"
  echo "  which issues its own TLS certificates. Point proxy domains at this host:"
  echo ""
  echo "    *.${AURORANET_DOMAIN}  CNAME  ${AURORANET_DOMAIN}"
  echo ""
  echo "  Open 51820/udp (optional) for peer-to-peer proxy connections."
  if [[ "$AURORANET_CROWDSEC" == "yes" ]]; then
    echo "  CrowdSec is running. Enable it per service in the dashboard under Access Control."
  fi
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" ]]; then
    echo "  CrowdSec AppSec is inspecting the dashboard, /api, and /oauth2."
    echo "  A request for /.env should return 403. The first Traefik start downloads the bouncer plugin."
    echo "  If you are locked out, recover over SSH. See https://docs.aurora-net.org/selfhosted/maintenance/crowdsec-dashboard#recovering-from-a-dashboard-lockout"
  fi
  return
}

init_environment() {
  check_openssl
  check_traefik_tag
  DOCKER_COMPOSE_COMMAND=$(check_docker_compose)

  if [[ -f .env ]] || [[ -f docker-compose.yml ]] || [[ -f config.yaml ]]; then
    echo "Generated files already exist in $(pwd)."
    echo "To add the proxy or traffic events to this installation, re-run with"
    echo "--enable-proxy or --enable-traffic-events."
    echo ""
    echo "If you want to reinitialize the environment, please remove them first:"
    echo "  $DOCKER_COMPOSE_COMMAND down --volumes # removes all containers and volumes"
    echo "  rm -rf .env docker-compose.yml config.yaml traefik"
    echo "Be aware this will remove all data from the database."
    exit 1
  fi

  require_eula_acceptance
  AURORANET_EULA_ACCEPTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  echo "AuroraNet Enterprise bootstrap"
  echo ""
  echo "Traffic flow:"
  echo "  Enables traffic events logging on the management server."
  echo "  When enabled, the AuroraNet stack also runs NATS along with two"
  echo "  additional containers: auroranet-receiver (the traffic log receiver"
  echo "  service) and auroranet-enricher (the traffic log enricher service)."
  echo "  It still has to be turned on from the dashboard settings afterwards."
  echo "  See https://docs.aurora-net.org/manage/activity/traffic-events-logging"
  AURORANET_TRAFFIC_FLOW=$(read_yes_no "Enable traffic flow" "n")

  echo ""
  echo "AuroraNet Proxy:"
  echo "  Exposes selected resources from your AuroraNet network to the internet."
  echo "  You choose which resources are exposed from the dashboard."
  AURORANET_PROXY=$(read_yes_no "Enable the AuroraNet Proxy" "n")
  AURORANET_CROWDSEC="no"
  AURORANET_CROWDSEC_APPSEC="no"
  if [[ "$AURORANET_PROXY" == "yes" ]]; then
    read_crowdsec_option
  fi

  echo ""
  AURORANET_DOMAIN=$(read_nb_domain)

  echo ""
  AURORANET_LETSENCRYPT_EMAIL=$(read_letsencrypt_email)

  echo ""

  AURORANET_LICENSE_KEY=$(read_secret "Enter license key (input hidden)")

  POSTGRES_USER="auroranet"
  POSTGRES_DB="auroranet"
  POSTGRES_PASSWORD=$(rand_secret)
  AURORANET_ENCRYPTION_KEY=$(rand_b64_key)
  AURORANET_SESSION_COOKIE_ENCRYPTION_KEY=$(rand_b64_key)
  AURORANET_RELAY_AUTH_SECRET=$(rand_secret)

  POSTGRES_DSN="host=postgres user=${POSTGRES_USER} password=${POSTGRES_PASSWORD} dbname=${POSTGRES_DB} port=5432 sslmode=disable TimeZone=UTC"
  AURORANET_RELAY_ENDPOINT="rels://${AURORANET_DOMAIN}:443"

  echo ""
  echo "Selected:"
  echo "  Traffic flow: ${AURORANET_TRAFFIC_FLOW}"
  echo "  Proxy:        ${AURORANET_PROXY}"
  echo "  CrowdSec:     ${AURORANET_CROWDSEC}"
  echo "  AppSec:       ${AURORANET_CROWDSEC_APPSEC}"
  echo "  Domain:       ${AURORANET_DOMAIN}"
  echo "  ACME email:   ${AURORANET_LETSENCRYPT_EMAIL}"
  echo ""
  echo "Rendering files into $(pwd) ..."
  ensure_crowdsec_dashboard_key
  install -m 600 /dev/null .env
  render_env >> .env
  render_docker_compose > docker-compose.yml
  mkdir -p traefik
  if [[ "$AURORANET_PROXY" == "yes" ]]; then
    render_traefik_proxy > traefik/proxy.yaml
  fi
  install -m 600 /dev/null config.yaml
  render_config_yaml >> config.yaml
  if [[ "$AURORANET_CROWDSEC_APPSEC" == "yes" ]]; then
    write_crowdsec_appsec_acquisition
  fi

  echo ""
  echo "Pulling images ..."
  $DOCKER_COMPOSE_COMMAND pull

  echo ""
  echo "Starting postgres ..."
  $DOCKER_COMPOSE_COMMAND up -d postgres
  sleep 2
  wait_postgres

  echo ""
  echo "Starting remaining services ..."
  up_all_but_proxy

  echo ""
  wait_for_license_verdict

  if [[ "$AURORANET_PROXY" == "yes" ]]; then
    echo ""
    start_proxy
  fi

  echo ""
  echo "Done."
  echo ""
  echo "Dashboard: https://${AURORANET_DOMAIN}"
  echo ""
  echo "Open the dashboard in a browser to complete the first-login owner setup."
  echo "All configuration and secrets are stored (mode 600) in $(pwd)/.env"
  if [[ "$AURORANET_PROXY" == "yes" ]]; then
    print_proxy_notes
  fi
  echo ""
  echo "Tail logs:"
  echo "  cd $(pwd) && $DOCKER_COMPOSE_COMMAND logs -f auroranet-server traefik"

  report_license_verdict

  if [[ "$LICENSE_VERDICT" == "rejected" ]]; then
    exit 1
  fi
  return
}

# service_block NAME prints a service's definition from the compose file on stdin.
service_block() {
  local name="$1"
  awk -v s="  ${name}:" '$0 == s { p = 1; print; next } p && (/^[^ ]/ || /^  [^ ]/) { exit } p'
  return
}

# enable_features adds the proxy and/or traffic events to the install in the
# current directory, restoring the backed-up files if any step fails.
enable_features() {
  local want_proxy="$1" want_flow="$2" f compose
  DOCKER_COMPOSE_COMMAND=$(check_docker_compose)

  for f in "${STACK_FILES[@]}"; do
    [[ -f "$f" ]] || die "$f not found in $(pwd). Run this from an existing installation directory."
  done
  grep -q '^# Generated by getting-started-enterprise.sh' .env || die ".env was not generated by getting-started-enterprise.sh."
  # Installs from before the move to Traefik run Caddy and can't be re-rendered.
  [[ -n "$(env_get AURORANET_TRAEFIK_IP)" ]] || die "This installation predates the Traefik layout and can't be updated in place."

  AURORANET_DOMAIN=$(env_get AURORANET_DOMAIN)
  AURORANET_LICENSE_SERVER_BASE_URL=$(env_get AURORANET_LICENSE_SERVER_BASE_URL)
  AURORANET_TRAFFIC_FLOW=$(env_get AURORANET_TRAFFIC_FLOW_ENABLED no)
  AURORANET_PROXY=$(env_get AURORANET_PROXY_ENABLED no)
  AURORANET_CROWDSEC=$(env_get AURORANET_CROWDSEC_ENABLED no)
  AURORANET_CROWDSEC_APPSEC=$(env_get AURORANET_CROWDSEC_APPSEC_ENABLED no)
  # A custom certificate counts only once Traefik mounts it and ACME is already gone,
  # so the re-render never removes a working Let's Encrypt setup.
  local traefik_block
  traefik_block=$(service_block traefik < docker-compose.yml)
  # Enabling features does not upgrade Traefik. Preserve the existing header policy,
  # including its absence on older releases that do not support these options.
  TRAEFIK_HEADER_CONFIG=$(printf '%s\n' "$traefik_block" | grep -Ei -- '--entrypoints\.[^.]+\.http\.(alias|underscore)headersstrategy=' || true)
  if ! grep -q certificatesresolvers <<< "$traefik_block"; then
    CUSTOM_TLS_CERTS=$(awk '/:\/certs:ro$/ { sub(/^ *- /, ""); sub(/:\/certs:ro$/, ""); print; exit }' <<< "$traefik_block")
  fi

  if [[ "$want_flow" == "yes" && "$AURORANET_TRAFFIC_FLOW" == "yes" ]]; then
    echo "Traffic events are already enabled."
    want_flow="no"
  fi
  # No token means an earlier proxy setup failed, so let it run again.
  if [[ "$want_proxy" == "yes" && -n "$(env_get AURORANET_PROXY_TOKEN)" ]]; then
    echo "The AuroraNet Proxy is already enabled."
    want_proxy="no"
  fi
  if [[ "$want_flow" == "no" && "$want_proxy" == "no" ]]; then
    exit 0
  fi

  if [[ "$want_flow" == "yes" ]]; then
    AURORANET_TRAFFIC_FLOW="yes"
  fi
  # A retry keeps the CrowdSec choice made at install time.
  if [[ "$want_proxy" == "yes" && "$AURORANET_PROXY" != "yes" ]]; then
    read_crowdsec_option
  fi
  if [[ "$want_proxy" == "yes" ]]; then
    AURORANET_PROXY="yes"
  fi

  compose=$(render_docker_compose)
  echo ""
  echo "Changes to docker-compose.yml:"
  printf '%s\n' "$compose" | diff -u docker-compose.yml - || true

  # Lines the new file drops are most likely local edits, so don't default to applying.
  local lost s restarts="" apply="y"
  lost=$(printf '%s\n' "$compose" | awk 'NR == FNR { keep[$0]; next } !($0 in keep)' - docker-compose.yml)
  if [[ -n "$lost" ]]; then
    echo ""
    echo "These lines are not in the new docker-compose.yml and will be lost:"
    printf '%s\n' "$lost"
    apply="n"
  fi
  for s in $($DOCKER_COMPOSE_COMMAND config --services); do
    if [[ "$(service_block "$s" < docker-compose.yml)" != "$(printf '%s\n' "$compose" | service_block "$s")" ]] \
      || [[ "$s" == "auroranet-server" && "$want_flow" == "yes" ]]; then
      restarts+=" $s"
    fi
  done
  echo ""
  if [[ -n "$restarts" ]]; then
    echo "These services will restart:${restarts}"
  fi
  if [[ "$(read_yes_no "Apply these changes?" "$apply")" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi

  BACKUP_SUFFIX=".bak.$(date -u +%Y%m%d%H%M%S)"
  for f in "${STACK_FILES[@]}" traefik/proxy.yaml; do
    if [[ -f "$f" ]]; then cp -p "$f" "$f$BACKUP_SUFFIX"; fi
  done
  trap rollback EXIT

  printf '%s\n' "$compose" > docker-compose.yml
  {
    ensure_crowdsec_dashboard_key
    echo "AURORANET_TRAFFIC_FLOW_ENABLED=${AURORANET_TRAFFIC_FLOW}"
    echo "AURORANET_PROXY_ENABLED=${AURORANET_PROXY}"
    echo "AURORANET_CROWDSEC_ENABLED=${AURORANET_CROWDSEC}"
    echo "AURORANET_CROWDSEC_APPSEC_ENABLED=${AURORANET_CROWDSEC_APPSEC}"
    render_env_dashboard_bouncer_key
    if [[ "$want_flow" == "yes" ]]; then render_env_flow; fi
    if [[ "$want_proxy" == "yes" ]]; then render_env_proxy; fi
  } | merge_env
  if [[ "$want_flow" == "yes" ]] && ! grep -q '^  trafficFlow:' config.yaml; then
    render_config_flow >> config.yaml
  fi
  mkdir -p traefik
  if [[ "$want_proxy" == "yes" ]]; then
    render_traefik_proxy > traefik/proxy.yaml
  fi
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" ]]; then
    write_crowdsec_appsec_acquisition
  fi

  up_all_but_proxy
  if [[ "$want_flow" == "yes" ]]; then
    # Compose does not notice changes to the bind-mounted config.yaml.
    $DOCKER_COMPOSE_COMMAND restart auroranet-server
  fi
  if [[ "$want_proxy" == "yes" ]]; then
    start_proxy
  fi
  trap - EXIT

  echo ""
  echo "Done. The previous files are kept with the ${BACKUP_SUFFIX} suffix."
  if [[ "$want_flow" == "yes" ]]; then
    echo ""
    echo "Traffic events still have to be turned on from the dashboard settings."
    echo "  See https://docs.aurora-net.org/manage/activity/traffic-events-logging"
  fi
  if [[ "$want_proxy" == "yes" ]]; then
    print_proxy_notes
  fi
  return
}

rollback() {
  local f
  echo "" > /dev/stderr
  echo "Enabling failed. Restoring the previous configuration ..." > /dev/stderr
  revoke_proxy_token
  # Files without a backup were created by this run.
  for f in "${STACK_FILES[@]}" traefik/proxy.yaml; do
    if [[ -f "$f$BACKUP_SUFFIX" ]]; then cp -p "$f$BACKUP_SUFFIX" "$f"; else rm -f "$f"; fi
  done
  if [[ -n "${APPSEC_ACQUIS_CREATED:-}" ]]; then
    rm -f "$APPSEC_ACQUIS_CREATED"
    rmdir crowdsec/acquis.d 2> /dev/null || true
    rmdir crowdsec 2> /dev/null || true
  fi
  $DOCKER_COMPOSE_COMMAND up -d --remove-orphans
  $DOCKER_COMPOSE_COMMAND restart auroranet-server
  return
}

# ------------------------------------------------------------------
# Renderers
# ------------------------------------------------------------------

render_env() {
  cat <<EOF
# Generated by getting-started-enterprise.sh
# Holds all configuration and secrets for the stack. Mode 600.

# AuroraNet On-Premise EULA acceptance
AURORANET_EULA_ACCEPTED=yes
AURORANET_EULA_ACCEPTED_AT=${AURORANET_EULA_ACCEPTED_AT}
AURORANET_EULA_URL=${AURORANET_EULA_URL}

# Features (change with --enable-proxy or --enable-traffic-events, not by hand)
AURORANET_TRAFFIC_FLOW_ENABLED=${AURORANET_TRAFFIC_FLOW}
AURORANET_PROXY_ENABLED=${AURORANET_PROXY}
AURORANET_CROWDSEC_ENABLED=${AURORANET_CROWDSEC}
AURORANET_CROWDSEC_APPSEC_ENABLED=${AURORANET_CROWDSEC_APPSEC:-no}

# Domain
AURORANET_DOMAIN=${AURORANET_DOMAIN}

# Reverse proxy (Traefik)
AURORANET_LETSENCRYPT_EMAIL=${AURORANET_LETSENCRYPT_EMAIL}
AURORANET_TRAEFIK_TAG=${AURORANET_TRAEFIK_TAG:-v3.7.18}
AURORANET_TRAEFIK_IP=${TRAEFIK_IP}

# Image tags. Default to "latest"
AURORANET_DASHBOARD_TAG=${AURORANET_DASHBOARD_TAG:-latest}
AURORANET_SERVER_TAG=${AURORANET_SERVER_TAG:-latest}
EOF

  if [[ "$AURORANET_TRAFFIC_FLOW" == "yes" ]]; then
    render_env_flow
  fi
  if [[ "$AURORANET_PROXY" == "yes" ]]; then
    printf '\n# AuroraNet Proxy (token and bouncer key are filled in after startup)\n'
    render_env_proxy
    render_env_dashboard_bouncer_key
  fi

  cat <<EOF

# License keys
EOF
  if [[ -n "${AURORANET_LICENSE_SERVER_BASE_URL:-}" ]]; then
    cat <<EOF
AURORANET_LICENSE_SERVER_BASE_URL=${AURORANET_LICENSE_SERVER_BASE_URL}
EOF
  fi
  cat <<EOF
AURORANET_LICENSE_KEY=${AURORANET_LICENSE_KEY}
EOF

  cat <<EOF

# Postgres
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
AURORANET_STORE_ENGINE_POSTGRES_DSN=${POSTGRES_DSN}

# Relay
AURORANET_RELAY_ENDPOINT=${AURORANET_RELAY_ENDPOINT}
AURORANET_RELAY_AUTH_SECRET=${AURORANET_RELAY_AUTH_SECRET}

# Datastore encryption
AURORANET_ENCRYPTION_KEY=${AURORANET_ENCRYPTION_KEY}

# Dashboard OIDC scopes
AURORANET_AUTH_SUPPORTED_SCOPES=${AURORANET_AUTH_SUPPORTED_SCOPES:-openid profile email groups}
EOF
  return
}

render_env_flow() {
  echo "AURORANET_ENRICHER_TAG=${AURORANET_ENRICHER_TAG:-latest}"
  echo "AURORANET_RECEIVER_TAG=${AURORANET_RECEIVER_TAG:-latest}"
  return
}

render_env_proxy() {
  echo "AURORANET_PROXY_TAG=${AURORANET_PROXY_TAG:-latest}"
  echo "AURORANET_PROXY_TOKEN="
  if [[ "$AURORANET_CROWDSEC" == "yes" ]]; then
    echo "AURORANET_CROWDSEC_TAG=${AURORANET_CROWDSEC_TAG:-v1.8.1}"
    echo "AURORANET_CROWDSEC_BOUNCER_KEY="
  fi
  return
}

render_env_dashboard_bouncer_key() {
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" && -n "${CROWDSEC_DASHBOARD_BOUNCER_KEY:-}" ]]; then
    echo "CROWDSEC_DASHBOARD_BOUNCER_KEY=${CROWDSEC_DASHBOARD_BOUNCER_KEY}"
  fi
  return
}

render_docker_compose() {
  {
    render_compose_header
    render_compose_common
    render_compose_server
    if [[ "$AURORANET_TRAFFIC_FLOW" == "yes" ]]; then
      render_compose_flow
    fi
    if [[ "$AURORANET_PROXY" == "yes" ]]; then
      render_compose_proxy
    fi
    render_compose_postgres
    render_compose_footer
  } | if [[ -n "${AURORANET_LICENSE_SERVER_BASE_URL:-}" ]]; then cat; else sed '/AURORANET_LICENSE_SERVER_BASE_URL/d'; fi \
    | if [[ -n "$CUSTOM_TLS_CERTS" ]]; then sed -e '/certificatesresolvers/d' -e '/certresolver/d'; else cat; fi
  return
}

render_compose_header() {
  cat <<'EOF'
x-default: &default
  restart: unless-stopped
  logging:
    driver: json-file
    options:
      max-size: '500m'
      max-file: '2'

services:
EOF
  return
}

render_compose_common() {
  local dashboard_middlewares="nb-security@docker"
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" ]]; then
    dashboard_middlewares="auroranet-dashboard-crowdsec@docker,nb-security@docker"
  fi
  cat <<'EOF'
  # Reverse proxy with automatic TLS via Let's Encrypt. Routes are declared as
  # labels on the services below and picked up through the Docker provider.
  traefik:
    <<: *default
    image: traefik:${AURORANET_TRAEFIK_TAG}
    container_name: auroranet-traefik
    networks:
      auroranet:
        ipv4_address: ${AURORANET_TRAEFIK_IP}
    command:
      # Logging
      - "--log.level=INFO"
      - "--accesslog=true"
      # Docker provider
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=auroranet"
      # Entrypoints
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.websecure.allowACMEByPass=true"
EOF
  # Installs that predate these options have no header config; don't leave a blank line.
  if [[ -n "$TRAEFIK_HEADER_CONFIG" ]]; then
    printf '%s\n' "$TRAEFIK_HEADER_CONFIG"
  fi
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" ]]; then
    printf '%s\n' "$TRAEFIK_APPSEC_PLUGIN_CONFIG"
  fi
  cat <<'EOF'
      # readTimeout bounds the whole request, and gRPC streams / relay WebSockets
      # never end one; idleTimeout would close the keep-alive connection they
      # are reused over. Entrypoint-wide is the only scope Traefik offers here.
      # writeTimeout is left alone: it already defaults to 0.
      - "--entrypoints.websecure.transport.respondingTimeouts.readTimeout=0"
      - "--entrypoints.websecure.transport.respondingTimeouts.idleTimeout=0"
      # HTTP to HTTPS redirect
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      # Let's Encrypt ACME
      - "--certificatesresolvers.letsencrypt.acme.email=${AURORANET_LETSENCRYPT_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      # Dynamic config in ./traefik: the proxy transport and an optional custom certificate
      - "--providers.file.directory=/etc/traefik/dynamic"
    ports:
      - '443:443'
      - '80:80'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - auroranet_traefik_letsencrypt:/letsencrypt
      - ./traefik:/etc/traefik/dynamic:ro
EOF
  if [[ -n "$CUSTOM_TLS_CERTS" ]]; then
    echo "      - ${CUSTOM_TLS_CERTS}:/certs:ro"
  fi
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" ]]; then
    cat <<'EOF'
    depends_on:
      crowdsec:
        condition: service_healthy
EOF
  fi
  cat <<'EOF'
    labels:
      - traefik.enable=true
      # Shared security headers, referenced by every AuroraNet router below. A
      # label-declared middleware only exists while its container runs, so this
      # lives on Traefik itself: declaring it on an app container would drop
      # every router referencing it whenever that container restarts.
      - traefik.http.middlewares.nb-security.headers.stsSeconds=3600
      - traefik.http.middlewares.nb-security.headers.stsIncludeSubdomains=true
      - traefik.http.middlewares.nb-security.headers.contentTypeNosniff=true
      - traefik.http.middlewares.nb-security.headers.browserXssFilter=true
      - traefik.http.middlewares.nb-security.headers.referrerPolicy=strict-origin-when-cross-origin
      - traefik.http.middlewares.nb-security.headers.customResponseHeaders.X-Frame-Options=SAMEORIGIN
      # Empty value strips the header. Only the dashboard's nginx sets one; the
      # server emits none. Do not quote it — "" would send a literal Server: "".
      - traefik.http.middlewares.nb-security.headers.customResponseHeaders.Server=
EOF
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" ]]; then
    cat <<'EOF'
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
  fi
  cat <<'EOF'

  dashboard:
    <<: *default
    image: ghcr.io/haxygame-coding/auroranet-dashboard-cloud:${AURORANET_DASHBOARD_TAG}
    container_name: auroranet-dashboard
    networks: [auroranet]
    labels:
      - traefik.enable=true
      # Dashboard catch-all: lowest priority so every route below wins
      - traefik.http.routers.auroranet-dashboard.rule=Host(`${AURORANET_DOMAIN}`)
      - traefik.http.routers.auroranet-dashboard.entrypoints=websecure
      - traefik.http.routers.auroranet-dashboard.tls=true
      - traefik.http.routers.auroranet-dashboard.tls.certresolver=letsencrypt
EOF
  printf '      - traefik.http.routers.auroranet-dashboard.middlewares=%s\n' "$dashboard_middlewares"
  cat <<'EOF'
      - traefik.http.routers.auroranet-dashboard.service=dashboard
      - traefik.http.routers.auroranet-dashboard.priority=1
      - traefik.http.services.dashboard.loadbalancer.server.port=80
    environment:
      - AURORANET_MGMT_API_ENDPOINT=https://${AURORANET_DOMAIN}
      - AURORANET_MGMT_GRPC_API_ENDPOINT=https://${AURORANET_DOMAIN}
      - AUTH_AUDIENCE=auroranet-dashboard
      - AUTH_CLIENT_ID=auroranet-dashboard
      - AUTH_CLIENT_SECRET=
      - AUTH_AUTHORITY=https://${AURORANET_DOMAIN}/oauth2
      - USE_AUTH0=false
      - AUTH_SUPPORTED_SCOPES=${AURORANET_AUTH_SUPPORTED_SCOPES}
      - AUTH_REDIRECT_URI=/nb-auth
      - AUTH_SILENT_REDIRECT_URI=/nb-silent-auth
      - AURORANET_TOKEN_SOURCE=accessToken
      - NGINX_SSL_PORT=443
      - LETSENCRYPT_DOMAIN=
      - LETSENCRYPT_EMAIL=

EOF
  return
}

render_compose_server() {
  local backend_paths='PathPrefix(`/relay`) || PathPrefix(`/ws-proxy/`)'
  # API and OAuth2 must not fall back to an uninspected router when AppSec fails.
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" != "yes" ]]; then
    backend_paths+=' || PathPrefix(`/api`) || PathPrefix(`/oauth2`)'
  fi
  cat <<'EOF'
  auroranet-server:
    <<: *default
    image: ghcr.io/haxygame-coding/auroranet-server-cloud:${AURORANET_SERVER_TAG}
    container_name: auroranet-server
    networks: [auroranet]
    depends_on:
      dashboard:
        condition: service_started
      postgres:
        condition: service_healthy
    ports:
      - '3478:3478/udp'
    volumes:
      - auroranet_data:/var/lib/auroranet
      - ./config.yaml:/etc/auroranet/config.yaml
    command: ["--config", "/etc/auroranet/config.yaml"]
    labels:
      - traefik.enable=true
      # Signal + Management gRPC (needs an h2c backend for HTTP/2 cleartext)
      - traefik.http.routers.auroranet-grpc.rule=Host(`${AURORANET_DOMAIN}`) && (PathPrefix(`/signalexchange.SignalExchange/`) || PathPrefix(`/management.ManagementService/`) || PathPrefix(`/management.ProxyService/`))
      - traefik.http.routers.auroranet-grpc.entrypoints=websecure
      - traefik.http.routers.auroranet-grpc.tls=true
      - traefik.http.routers.auroranet-grpc.tls.certresolver=letsencrypt
      - traefik.http.routers.auroranet-grpc.middlewares=nb-security@docker
      - traefik.http.routers.auroranet-grpc.service=auroranet-server-h2c
      - traefik.http.routers.auroranet-grpc.priority=100
      # HTTP backend router
EOF
  printf '      - traefik.http.routers.auroranet-backend.rule=Host(`${AURORANET_DOMAIN}`) && (%s)\n' "$backend_paths"
  cat <<'EOF'
      - traefik.http.routers.auroranet-backend.entrypoints=websecure
      - traefik.http.routers.auroranet-backend.tls=true
      - traefik.http.routers.auroranet-backend.tls.certresolver=letsencrypt
      - traefik.http.routers.auroranet-backend.middlewares=nb-security@docker
      - traefik.http.routers.auroranet-backend.service=auroranet-server
      - traefik.http.routers.auroranet-backend.priority=100
EOF
  if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" ]]; then
    cat <<'EOF'
      - traefik.http.routers.auroranet-dashboard-api.rule=Host(`${AURORANET_DOMAIN}`) && (PathPrefix(`/api`) || PathPrefix(`/oauth2`))
      - traefik.http.routers.auroranet-dashboard-api.entrypoints=websecure
      - traefik.http.routers.auroranet-dashboard-api.tls=true
      - traefik.http.routers.auroranet-dashboard-api.tls.certresolver=letsencrypt
      - traefik.http.routers.auroranet-dashboard-api.service=auroranet-server
      - traefik.http.routers.auroranet-dashboard-api.middlewares=auroranet-dashboard-crowdsec@docker,nb-security@docker
      - traefik.http.routers.auroranet-dashboard-api.priority=110
EOF
  fi
  cat <<'EOF'
      # Services
      - traefik.http.services.auroranet-server.loadbalancer.server.port=80
      - traefik.http.services.auroranet-server-h2c.loadbalancer.server.port=80
      - traefik.http.services.auroranet-server-h2c.loadbalancer.server.scheme=h2c
    environment:
      - NB_LICENSE_KEY=${AURORANET_LICENSE_KEY}
      - AURORANET_LICENSE_SERVER_BASE_URL=${AURORANET_LICENSE_SERVER_BASE_URL}

EOF
  return
}

render_compose_flow() {
  cat <<'EOF'
  nats:
    <<: *default
    image: nats:2
    container_name: auroranet-nats
    networks: [auroranet]
    volumes:
      - auroranet_nats_data:/data
    command: ["-m", "8222", "--jetstream", "--store_dir", "/data"]

  enricher:
    <<: *default
    image: ghcr.io/haxygame-coding/flow-enricher-cloud:${AURORANET_ENRICHER_TAG}
    container_name: auroranet-enricher
    networks: [auroranet]
    depends_on:
      postgres:
        condition: service_healthy
      nats:
        condition: service_started
    volumes:
      - auroranet_enricher:/var/lib/auroranet
    environment:
      - NB_LICENSE_KEY=${AURORANET_LICENSE_KEY}
      - AURORANET_LICENSE_SERVER_BASE_URL=${AURORANET_LICENSE_SERVER_BASE_URL}
      - NB_DATADIR=/var/lib/auroranet
      - NB_MANAGEMENT_STORE_ENGINE=postgres
      - NB_MANAGEMENT_POSTGRES_DSN=${AURORANET_STORE_ENGINE_POSTGRES_DSN}
      - AURORANET_STORE_ENGINE_POSTGRES_DSN=${AURORANET_STORE_ENGINE_POSTGRES_DSN}
      - NB_TRAFFIC_EVENT_POSTGRES_DSN=${AURORANET_STORE_ENGINE_POSTGRES_DSN}
      - NB_TRAFFIC_EVENT_STORE_ENGINE=postgres
      - NB_MANAGEMENT_STORE_KEY=${AURORANET_ENCRYPTION_KEY}
      - NB_FLOW_ADAPTER_TYPE=nats
      - NB_FLOW_NATS_ENDPOINTS=nats://nats:4222
      - NB_FLOW_NATS_STREAM=traffic-events
      - NB_METRICS_PORT=9091
      - NB_PERSISTENCE_RETENTION_PERIOD=168h

  receiver:
    <<: *default
    image: ghcr.io/haxygame-coding/flow-receiver-cloud:${AURORANET_RECEIVER_TAG}
    container_name: auroranet-receiver
    networks: [auroranet]
    depends_on:
      nats:
        condition: service_started
    environment:
      - NB_LICENSE_KEY=${AURORANET_LICENSE_KEY}
      - AURORANET_LICENSE_SERVER_BASE_URL=${AURORANET_LICENSE_SERVER_BASE_URL}
      - NB_FLOW_LISTEN_PORT=80
      - NB_FLOW_ADAPTER_TYPE=nats
      - NB_FLOW_NATS_ENDPOINTS=nats://nats:4222
      - NB_FLOW_NATS_STREAM=traffic-events
      - NB_FLOW_AUTH_SECRET=${AURORANET_RELAY_AUTH_SECRET}
    labels:
      - traefik.enable=true
      # Flow receiver gRPC (h2c backend)
      - traefik.http.routers.auroranet-flow.rule=Host(`${AURORANET_DOMAIN}`) && PathPrefix(`/flow.FlowService/`)
      - traefik.http.routers.auroranet-flow.entrypoints=websecure
      - traefik.http.routers.auroranet-flow.tls=true
      - traefik.http.routers.auroranet-flow.tls.certresolver=letsencrypt
      - traefik.http.routers.auroranet-flow.middlewares=nb-security@docker
      - traefik.http.routers.auroranet-flow.service=auroranet-flow-h2c
      - traefik.http.routers.auroranet-flow.priority=100
      - traefik.http.services.auroranet-flow-h2c.loadbalancer.server.port=80
      - traefik.http.services.auroranet-flow-h2c.loadbalancer.server.scheme=h2c

EOF
  return
}

render_compose_proxy() {
  cat <<'EOF'
  # Traefik passes TLS for every other domain through to the proxy, which issues
  # its own certificates. PROXY protocol v2 preserves the client IP.
  proxy:
    <<: *default
    image: ghcr.io/haxygame-coding/auroranet-proxy:${AURORANET_PROXY_TAG}
    container_name: auroranet-proxy
    networks: [auroranet]
    depends_on:
      auroranet-server:
        condition: service_started
    ports:
      - '51820:51820/udp'
    volumes:
      - auroranet_proxy_certs:/certs
    labels:
      - traefik.enable=true
      - traefik.tcp.routers.proxy-passthrough.rule=HostSNI(`*`)
      - traefik.tcp.routers.proxy-passthrough.entrypoints=websecure
      - traefik.tcp.routers.proxy-passthrough.tls.passthrough=true
      - traefik.tcp.routers.proxy-passthrough.service=proxy-tls
      - traefik.tcp.routers.proxy-passthrough.priority=1
      - traefik.tcp.services.proxy-tls.loadbalancer.server.port=8443
      - traefik.tcp.services.proxy-tls.loadbalancer.serverstransport=pp-v2@file
    environment:
      # Plaintext gRPC over the internal network, not the public address.
      - NB_PROXY_MANAGEMENT_ADDRESS=http://auroranet-server:80
      - NB_PROXY_ALLOW_INSECURE=true
      - NB_PROXY_TOKEN=${AURORANET_PROXY_TOKEN}
      - NB_PROXY_DOMAIN=${AURORANET_DOMAIN}
      - NB_PROXY_ADDRESS=:8443
      - NB_PROXY_CERTIFICATE_DIRECTORY=/certs
      - NB_PROXY_ACME_CERTIFICATES=true
      - NB_PROXY_FORWARDED_PROTO=https
      - NB_PROXY_PROXY_PROTOCOL=true
      - NB_PROXY_TRUSTED_PROXIES=${AURORANET_TRAEFIK_IP}
EOF
  if [[ "$AURORANET_CROWDSEC" == "yes" ]]; then
    cat <<'EOF'
      - NB_PROXY_CROWDSEC_API_URL=http://crowdsec:8080
      - NB_PROXY_CROWDSEC_API_KEY=${AURORANET_CROWDSEC_BOUNCER_KEY}

  crowdsec:
    <<: *default
    image: crowdsecurity/crowdsec:${AURORANET_CROWDSEC_TAG}
    container_name: auroranet-crowdsec
    networks: [auroranet]
EOF
    if [[ "${AURORANET_CROWDSEC_APPSEC:-}" == "yes" ]]; then
      cat <<'EOF'
    environment:
      - "COLLECTIONS=crowdsecurity/linux crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules"
      - BOUNCER_KEY_auroranet_dashboard=${CROWDSEC_DASHBOARD_BOUNCER_KEY}
    volumes:
      - auroranet_crowdsec_config:/etc/crowdsec
      - auroranet_crowdsec_data:/var/lib/crowdsec/data
      - ./crowdsec/acquis.d:/etc/crowdsec/acquis.d:ro
    healthcheck:
      test: ["CMD-SHELL", "cscli lapi status >/dev/null 2>&1 && bash -c '</dev/tcp/127.0.0.1/7422'"]
      interval: 10s
      timeout: 5s
      retries: 15
      start_period: 30s
EOF
    else
      cat <<'EOF'
    environment:
      - COLLECTIONS=crowdsecurity/linux
    volumes:
      - auroranet_crowdsec_config:/etc/crowdsec
      - auroranet_crowdsec_data:/var/lib/crowdsec/data
    healthcheck:
      test: ["CMD", "cscli", "lapi", "status"]
      interval: 10s
      timeout: 5s
      retries: 15
EOF
    fi
  fi
  echo ""
  return
}

render_compose_postgres() {
  cat <<'EOF'
  postgres:
    <<: *default
    image: postgres:17
    container_name: auroranet-postgres
    networks: [auroranet]
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
    volumes:
      - auroranet_postgres:/var/lib/postgresql/data

EOF
  return
}

render_compose_footer() {
  cat <<'EOF'
volumes:
  auroranet_data:
EOF
  if [[ "$AURORANET_TRAFFIC_FLOW" == "yes" ]]; then
    cat <<'EOF'
  auroranet_nats_data:
  auroranet_enricher:
EOF
  fi
  if [[ "$AURORANET_PROXY" == "yes" ]]; then
    echo "  auroranet_proxy_certs:"
  fi
  if [[ "$AURORANET_CROWDSEC" == "yes" ]]; then
    printf '  %s:\n' auroranet_crowdsec_config auroranet_crowdsec_data
  fi
  cat <<'EOF'
  auroranet_postgres:
  auroranet_traefik_letsencrypt:

networks:
  auroranet:
    name: auroranet
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24
          gateway: 172.30.0.1
EOF
  return
}

render_config_yaml() {
  cat <<EOF
# AuroraNet Enterprise server configuration.
# Generated by getting-started-enterprise.sh. Mode 600.

server:
  listenAddress: ":80"
  exposedAddress: "https://${AURORANET_DOMAIN}:443"

  metricsPort: 9090
  healthcheckAddress: ":9000"

  logLevel: "info"
  logFile: "console"

  # TLS is terminated by Traefik in front; leave this block empty.
  tls:
    certFile: ""
    keyFile: ""
    letsencrypt:
      enabled: false

  authSecret: "${AURORANET_RELAY_AUTH_SECRET}"
  dataDir: "/var/lib/auroranet/"

  disableAnonymousMetrics: false
  disableGeoliteUpdate: false

  auth:
    issuer: "https://${AURORANET_DOMAIN}/oauth2"
    localAuthDisabled: false
    signKeyRefreshEnabled: false
    sessionCookieEncryptionKey: "${AURORANET_SESSION_COOKIE_ENCRYPTION_KEY}"
    dashboardRedirectURIs:
      - "https://${AURORANET_DOMAIN}/nb-auth"
      - "https://${AURORANET_DOMAIN}/nb-silent-auth"
    cliRedirectURIs:
      - "http://localhost:53000/"

  # Trust X-Forwarded-* only from the Traefik container's static address. Both
  # keys must stay in step with the ipv4_address pinned in docker-compose.yml:
  # trustedPeers restricts which sources may supply forwarded headers. Leaving
  # it unset trusts all IPv4 and IPv6 sources.
  reverseProxy:
    trustedPeers:
      - "${TRAEFIK_IP}/32"
    trustedHTTPProxies:
      - "${TRAEFIK_IP}/32"

  store:
    engine: "postgres"
    dsn: "${POSTGRES_DSN}"
    encryptionKey: "${AURORANET_ENCRYPTION_KEY}"

  activityStore:
    engine: "postgres"
    dsn: "${POSTGRES_DSN}"
EOF

  if [[ "$AURORANET_TRAFFIC_FLOW" == "yes" ]]; then
    render_config_flow
  fi
  return
}

render_config_flow() {
  cat <<EOF

  trafficFlow:
    enabled: true
    address: "https://${AURORANET_DOMAIN}:443"
    interval: "60s"
EOF
  return
}

render_traefik_proxy() {
  cat <<'EOF'
tcp:
  serversTransports:
    pp-v2:
      proxyProtocol:
        version: 2
EOF
  return
}

usage() {
  cat <<EOF
Usage: $0 [--enable-proxy] [--enable-traffic-events]

Without flags, bootstraps a new AuroraNet Enterprise stack in the current
directory. With flags, turns the feature on for the existing installation in
the current directory.

  --enable-proxy           add the AuroraNet Proxy, optionally with CrowdSec and AppSec
  --enable-traffic-events  add traffic events logging (NATS, receiver, enricher)
  -h, --help               show this help
EOF
  return
}

main() {
  local enable_proxy="no" enable_flow="no"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --enable-proxy) enable_proxy="yes" ;;
      --enable-traffic-events) enable_flow="yes" ;;
      -h | --help) usage; exit 0 ;;
      *) usage > /dev/stderr; exit 1 ;;
    esac
    shift
  done

  if [[ "$enable_proxy" == "no" && "$enable_flow" == "no" ]]; then
    init_environment
  else
    enable_features "$enable_proxy" "$enable_flow"
  fi
  return
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  set -e
  set -o pipefail
  main "$@"
fi
