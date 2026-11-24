#!/usr/bin/env bash
# Regenerates the Homebrew formula for a released AuroraNet version.
#
# Usage: publish-homebrew-formula.sh <version> <release-dir> [<tap-dir>]
#
#   <version>      version without the leading "v"
#   <release-dir>  directory holding auroranet_<version>_<os>_<arch>.tar.gz
#   <tap-dir>      existing checkout of the tap; when omitted the script clones
#                  haxygame-coding/homebrew-tap with HOMEBREW_TAP_GITHUB_TOKEN,
#                  commits Formula/auroranet.rb and pushes it
#
# The formula points at the release archives, so it has to run once they were
# built. Homebrew runs on Linux, so the formula lists the Linux architectures it
# supports; macOS is not a supported platform.
set -euo pipefail

VERSION="${1:?usage: $0 <version> <release-dir> [<tap-dir>]}"
RELEASE_DIR="${2:?usage: $0 <version> <release-dir> [<tap-dir>]}"
TAP_DIR="${3:-}"

readonly OWNER="haxygame-coding"
readonly TAP_REPO="homebrew-tap"
readonly TAP_URL="https://github.com/${OWNER}/${TAP_REPO}.git"
readonly FORMULA_PATH="Formula/auroranet.rb"
readonly ARCHIVE_BASE="https://github.com/${OWNER}/AuroraNet/releases/download/v${VERSION}"

managed_tap=false

sha256_of() {
    local archive="${RELEASE_DIR}/auroranet_${VERSION}_$1_$2.tar.gz"
    if [ ! -f "$archive" ]; then
        echo "missing release archive: $archive" >&2
        exit 1
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$archive" | cut -d' ' -f1
    else
        shasum -a 256 "$archive" | cut -d' ' -f1
    fi
}

LINUX_AMD64=$(sha256_of linux amd64)
LINUX_ARM64=$(sha256_of linux arm64)
readonly LINUX_AMD64 LINUX_ARM64

if [ -z "$TAP_DIR" ]; then
    managed_tap=true
    token="${HOMEBREW_TAP_GITHUB_TOKEN:-}"
    if [ -z "$token" ]; then
        echo "HOMEBREW_TAP_GITHUB_TOKEN is not set" >&2
        exit 1
    fi
    TAP_DIR="$(mktemp -d)/tap"
    # The token goes through a credential helper so it never appears in the
    # clone URL, which git prints in error messages.
    helper="!f() { echo username=x-access-token; echo password=${token}; }; f"
    git -c "credential.helper=${helper}" clone --depth 1 "$TAP_URL" "$TAP_DIR"
    git -C "$TAP_DIR" config credential.helper "$helper"
fi

mkdir -p "$TAP_DIR/$(dirname "$FORMULA_PATH")"

cat >"$TAP_DIR/$FORMULA_PATH" <<EOF
class Auroranet < Formula
  desc "AuroraNet client"
  homepage "https://aurora-net.org/"
  version "${VERSION}"
  license "BSD-3-Clause"

  on_linux do
    on_arm do
      url "${ARCHIVE_BASE}/auroranet_${VERSION}_linux_arm64.tar.gz"
      sha256 "${LINUX_ARM64}"
    end

    on_intel do
      url "${ARCHIVE_BASE}/auroranet_${VERSION}_linux_amd64.tar.gz"
      sha256 "${LINUX_AMD64}"
    end
  end

  def install
    bin.install "auroranet"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/auroranet version")
  end
end
EOF

echo "wrote $TAP_DIR/$FORMULA_PATH"

# A checkout was handed over, so rendering the formula is all that was asked for.
if [ "$managed_tap" = false ]; then
    exit 0
fi

git -C "$TAP_DIR" config user.name "AuroraNet"
git -C "$TAP_DIR" config user.email "dev@aurora-net.org"
git -C "$TAP_DIR" add "$FORMULA_PATH"
if git -C "$TAP_DIR" diff --cached --quiet; then
    echo "formula already up to date"
    exit 0
fi
git -C "$TAP_DIR" commit -m "auroranet ${VERSION}"
git -C "$TAP_DIR" push origin HEAD
