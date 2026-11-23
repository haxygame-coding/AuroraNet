#!/usr/bin/env bash
# Builds the AuroraNet v1 release artifacts locally.
#
# Usage: packaging/build-release.sh [--docker] [--msi] [--sign]
#   --docker  also build the server and dashboard images
#   --msi     also build the Windows MSI (needs Docker + internet)
#   --sign    GPG-sign SHA256SUMS and every artifact
#
# Environment: AURORANET_VERSION (default 1.0.0), AURORANET_GHCR (default
# ghcr.io/haxygame), GO, NFPM, GPG_KEY (signing key id).
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
VERSION="${AURORANET_VERSION:-1.0.0}"
GHCR="${AURORANET_GHCR:-ghcr.io/haxygame}"
GO="${GO:-go}"
NFPM="${NFPM:-nfpm}"
DIST="$REPO_ROOT/dist/release"
BIN="$REPO_ROOT/dist"
LDFLAGS="-s -w -X github.com/netbirdio/netbird/version.version=$VERSION"

DO_DOCKER=0
DO_MSI=0
DO_SIGN=0
for arg in "$@"; do
  case "$arg" in
    --docker) DO_DOCKER=1 ;;
    --msi) DO_MSI=1 ;;
    --sign) DO_SIGN=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$DIST" "$BIN/auroranet-windows-amd64"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

build_binaries() {
  step "Building the Linux client ($VERSION)"
  CGO_ENABLED=0 "$GO" build -trimpath -ldflags "$LDFLAGS" -o "$BIN/auroranet-linux-amd64" ./client

  step "Building the Windows client ($VERSION)"
  CGO_ENABLED=0 GOOS=windows GOARCH=amd64 "$GO" build -trimpath -ldflags "$LDFLAGS" \
    -o "$BIN/auroranet-windows-amd64/auroranet.exe" ./client

  step "Building the combined server ($VERSION)"
  CGO_ENABLED=1 "$GO" build -trimpath -ldflags "$LDFLAGS" -o "$BIN/auroranet-server-linux-amd64" ./combined
  mkdir -p "$BIN/linux/amd64"
  cp "$BIN/auroranet-server-linux-amd64" "$BIN/linux/amd64/auroranet-server"
}

build_deb() {
  step "Building the Debian package"
  # nfpm does not expand environment variables inside contents.src, so resolve
  # the config into a temporary copy first.
  local cfg="$BIN/nfpm-resolved.yaml"
  sed -e "s|\${AURORANET_VERSION}|$VERSION|g" \
      -e "s|\${AURORANET_BINARY}|$BIN/auroranet-linux-amd64|g" \
      packaging/nfpm.yaml > "$cfg"
  "$NFPM" package --config "$cfg" --packager deb \
    --target "$DIST/auroranet_${VERSION}_amd64.deb"
}

build_arch() {
  step "Building the Arch package"
  local work="$REPO_ROOT/packaging/arch"
  cp "$BIN/auroranet-linux-amd64" "$work/auroranet-linux-amd64"
  cp "$REPO_ROOT/LICENSE" "$work/LICENSE"
  cp "$REPO_ROOT/packaging/README.md" "$work/README.md"
  ( cd "$work" && sed -i "s|^pkgver=.*|pkgver=$VERSION|" PKGBUILD && makepkg --force --nodeps --noconfirm >/dev/null )
  cp "$work"/auroranet-"$VERSION"-1-x86_64.pkg.tar.zst "$DIST"/
  rm -f "$work/auroranet-linux-amd64" "$work/LICENSE" "$work/README.md" "$work"/*.pkg.tar.zst
}

build_msi() {
  step "Building the Windows MSI"
  # wintun provides the TUN driver the client loads at runtime.
  if [[ ! -f "$BIN/auroranet-windows-amd64/wintun.dll" ]]; then
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL https://www.wintun.net/builds/wintun-0.14.1.zip -o "$tmp/wintun.zip"
    unzip -j -o "$tmp/wintun.zip" '*/bin/amd64/wintun.dll' -d "$BIN/auroranet-windows-amd64" >/dev/null
    rm -rf "$tmp"
  fi
  # wixl (msitools) builds WiX 3 schema MSIs on Linux, including ServiceInstall.
  sed "s|@VERSION@|$VERSION|" client/auroranet.wxs > "$BIN/auroranet-msi.wxs"
  docker run --rm -v "$REPO_ROOT:/src" -v "$BIN/auroranet-msi.wxs:/tmp/auroranet.wxs:ro" \
    -w /src archlinux:latest \
    bash -lc 'pacman -Sy --noconfirm --quiet msitools >/dev/null 2>&1 && wixl -o dist/release/auroranet_'$VERSION'_windows_amd64.msi /tmp/auroranet.wxs'
}

build_images() {
  step "Building the server image"
  # The Dockerfile expects the GoReleaser layout: <platform>/auroranet-server,
  # so the build context is dist/ rather than the repository root.
  docker build -f "$REPO_ROOT/combined/Dockerfile" --build-arg TARGETPLATFORM=linux/amd64 \
    -t "$GHCR/auroranet-server:$VERSION" -t "$GHCR/auroranet-server:latest" "$BIN"

  step "Building the dashboard image"
  docker build -f docker/Dockerfile \
    -t "$GHCR/auroranet-dashboard:$VERSION" -t "$GHCR/auroranet-dashboard:latest" \
    "$REPO_ROOT/../dashboard-2.98.0"
}

checksums_and_sign() {
  step "Writing checksums"
  ( cd "$DIST" && sha256sum *.deb *.pkg.tar.zst *.msi > SHA256SUMS
    sha256sum -c SHA256SUMS >/dev/null )

  if [[ "$DO_SIGN" == "1" ]]; then
    step "Signing with GPG"
    local key="${GPG_KEY:-}"
    local keyargs=()
    [[ -n "$key" ]] && keyargs=(--local-user "$key")
    ( cd "$DIST"
      for f in *; do
        [[ "$f" == *.asc ]] && continue
        gpg --batch --yes --armor --detach-sign "${keyargs[@]}" "$f"
      done )
  fi
  ls -la "$DIST"
}

build_binaries
build_deb
build_arch
[[ "$DO_MSI" == "1" ]] && build_msi
[[ "$DO_DOCKER" == "1" ]] && build_images
checksums_and_sign
